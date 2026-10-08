import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:project_echo/features/onboarding/data/voice_preference.dart';

/// Echo's natural voice: a Piper voice for each of the owner's four voices
/// in each accent, downloaded when the owner asks for it and run on the
/// phone. Until then, and if it's removed, Echo speaks with the phone's own
/// voice.
///
/// Each was picked for the cleanest sound among Piper's English voices (no
/// steady high-pitched tone under the speech).
class NaturalVoice {
  NaturalVoice._();
  static final instance = NaturalVoice._();

  /// The download for one voice, for the button.
  static const downloadLabel = '64 MB';

  /// The Piper voice being downloaded ([piperVoice]), if one is.
  final installing = ValueNotifier<String?>(null);

  /// 0..1 while [installing] downloads and unpacks, null otherwise.
  final progress = ValueNotifier<double?>(null);

  /// Ticks whenever a voice is added or removed, to check [modelDir] again.
  final changed = ValueNotifier<int>(0);

  CancelToken? _cancel;

  /// The install under way, so another can wait for it to stop.
  Future<void>? _running;

  Future<Directory> _voicesDir() async =>
      Directory('${(await getApplicationSupportDirectory()).path}/voices');

  /// [pref]'s voice's folder once fully unpacked, else null.
  Future<String?> modelDir(VoicePreference pref) async {
    final voices = await _voicesDir();
    await _removeKokoro(voices);
    final dir = '${voices.path}/${_folder(piperVoice(pref))}';
    final ready = await File('$dir/.ready').exists();
    return ready ? dir : null;
  }

  /// Downloads [pref]'s voice. Asking for another voice mid-download stops
  /// that one first: only the voice the owner has chosen is fetched.
  Future<void> install(VoicePreference pref) async {
    final voice = piperVoice(pref);
    if (installing.value == voice) return;
    if (_running != null) {
      cancelInstall();
      await _running!.catchError((_) {});
    }
    final run = _install(voice);
    _running = run;
    try {
      await run;
    } finally {
      if (identical(_running, run)) _running = null;
    }
  }

  Future<void> _install(String voice) async {
    installing.value = voice;
    progress.value = 0;
    final name = _folder(voice);
    final voices = await _voicesDir();
    await voices.create(recursive: true);
    final archive = File('${voices.path}/$name.tar.bz2');
    _cancel = CancelToken();
    try {
      try {
        await _download(
          'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/'
          '$name.tar.bz2',
          archive,
          _cancel!,
        );
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) return; // the owner cancelled
        debugPrint('Natural voice download failed: $e');
        rethrow;
      }
      await Isolate.run(() => _unpack(archive.path, voices.path));
      await File('${voices.path}/$name/.ready').writeAsString('ok');
      changed.value++;
    } catch (e) {
      debugPrint('Natural voice install failed: $e');
      rethrow;
    } finally {
      if (await archive.exists()) await archive.delete();
      progress.value = null;
      installing.value = null;
      _cancel = null;
    }
  }

  static String _folder(String voice) => 'vits-piper-$voice';

  /// The Kokoro voice Echo used before Piper, 350 MB: gone for good.
  static Future<void> _removeKokoro(Directory voices) async {
    if (!await voices.exists()) return;
    await for (final e in voices.list()) {
      if (e is Directory && e.path.split('/').last.startsWith('kokoro')) {
        await e.delete(recursive: true);
      }
    }
  }

  /// Downloads the archive into [file], resuming from where a dropped
  /// connection left off rather than starting again.
  Future<void> _download(String url, File file, CancelToken cancel) async {
    const attempts = 5;
    final dio = Dio();
    for (var attempt = 1; ; attempt++) {
      final have = await file.exists() ? await file.length() : 0;
      try {
        final response = await dio.get<ResponseBody>(
          url,
          cancelToken: cancel,
          options: Options(
            responseType: ResponseType.stream,
            headers: {if (have > 0) 'range': 'bytes=$have-'},
          ),
        );
        // A server that ignores the range sends the whole file again.
        final resumed = response.statusCode == 206;
        final total =
            (resumed ? have : 0) +
            (int.tryParse(response.headers.value('content-length') ?? '') ?? 0);
        final sink = file.openWrite(
          mode: resumed ? FileMode.append : FileMode.write,
        );
        var got = resumed ? have : 0;
        try {
          await for (final chunk in response.data!.stream) {
            sink.add(chunk);
            got += chunk.length;
            // The last tenth is unpacking.
            if (total > 0) progress.value = 0.9 * got / total;
          }
        } finally {
          await sink.close();
        }
        return;
      } catch (e) {
        // A dropped connection can surface from the stream itself, not
        // only from Dio, so anything but a cancel is retried.
        final cancelled = e is DioException && CancelToken.isCancel(e);
        if (cancelled || attempt == attempts) rethrow;
        debugPrint('Natural voice download dropped, resuming: $e');
        await Future<void>.delayed(Duration(seconds: 2 * attempt));
      }
    }
  }

  void cancelInstall() => _cancel?.cancel();

  /// Removes every downloaded voice.
  Future<void> remove() async {
    final voices = await _voicesDir();
    if (await voices.exists()) await voices.delete(recursive: true);
    changed.value++;
  }

  /// bzip2 to a temporary tar beside it, then the tar onto disk, streamed so
  /// the archive never sits in memory whole.
  static Future<void> _unpack(String bz2Path, String outDir) async {
    final tarPath = '$bz2Path.tar';
    final input = InputFileStream(bz2Path);
    final output = OutputFileStream(tarPath);
    BZip2Decoder().decodeStream(input, output);
    await input.close();
    await output.close();
    final tar = InputFileStream(tarPath);
    await extractArchiveToDisk(TarDecoder().decodeStream(tar), outDir);
    await tar.close();
    await File(tarPath).delete();
  }
}

/// Whether the owner's accent is spoken the British way. Piper's English is
/// American or British; Indian goes American, Australian and Irish British.
bool britishVoice(VoicePreference pref) => switch (pref.accent) {
  EchoAccent.us || EchoAccent.india => false,
  EchoAccent.uk || EchoAccent.australia || EchoAccent.ireland => true,
};

/// The Piper voice for the owner's chosen voice and accent: Aria and Sage
/// are women, Atlas and Nova men.
String piperVoice(VoicePreference pref) {
  const american = [
    'en_US-lessac-medium',
    'en_US-kristin-medium',
    'en_US-ryan-medium',
    'en_US-norman-medium',
  ];
  const british = [
    'en_GB-alba-medium',
    'en_GB-jenny_dioco-medium',
    'en_GB-northern_english_male-medium',
    'en_GB-alan-medium',
  ];
  return (britishVoice(pref) ? british : american)[pref.voice.voiceIndex];
}

/// The speed slider (0..1, centre is normal) as Piper's speed.
double piperSpeed(VoicePreference pref) =>
    0.85 + 0.35 * pref.speed.clamp(0.0, 1.0);

/// The accents Piper speaks: the others are heard as their nearest (see
/// [britishVoice]).
const piperAccents = [EchoAccent.us, EchoAccent.uk];

/// [accent] as the Piper accent it's heard in.
EchoAccent piperAccent(EchoAccent accent) =>
    britishVoice(VoicePreference.fallback.copyWith(accent: accent))
    ? EchoAccent.uk
    : EchoAccent.us;

/// A few seconds of [pref]'s natural voice saying its hello, bundled so it can
/// be heard before the voice is downloaded. For audioplayers' AssetSource.
String voiceSampleAsset(VoicePreference pref) =>
    'voice_samples/${piperVoice(pref)}.m4a';

/// How fast to play [voiceSampleAsset] for [pref]'s speed: the samples were
/// made at the slider's centre.
double voiceSampleRate(VoicePreference pref) =>
    piperSpeed(pref) / piperSpeed(VoicePreference.fallback);
