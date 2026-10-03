import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:project_echo/features/onboarding/data/voice_preference.dart';

/// Echo's natural voice: the Kokoro v1.0 model, downloaded when the owner
/// asks for it and run on the phone. Until then, and if it's removed, Echo
/// speaks with the phone's own voice.
///
/// The full-size model, not the compressed (int8) one: the compressed one
/// whines at 4.8 and 9.6 kHz and runs slower on phone chips.
class NaturalVoice {
  NaturalVoice._();
  static final instance = NaturalVoice._();

  static const _name = 'kokoro-multi-lang-v1_0';

  /// Earlier versions, removed when this one is installed.
  static const _older = ['kokoro-int8-en-v0_19'];
  static const _url =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/$_name.tar.bz2';

  /// The download, for the button: "98 MB".
  static const downloadLabel = '350 MB';

  /// 0..1 while downloading and unpacking, null otherwise.
  final progress = ValueNotifier<double?>(null);

  /// Whether it's ready to speak, kept current for the Settings switch.
  final installed = ValueNotifier<bool>(false);

  CancelToken? _cancel;

  Future<Directory> _voicesDir() async =>
      Directory('${(await getApplicationSupportDirectory()).path}/voices');

  /// The model's folder once fully unpacked, else null.
  Future<String?> modelDir() async {
    final dir = '${(await _voicesDir()).path}/$_name';
    final ready = await File('$dir/.ready').exists();
    installed.value = ready;
    return ready ? dir : null;
  }

  Future<void> install() async {
    if (progress.value != null) return;
    progress.value = 0;
    final voices = await _voicesDir();
    await voices.create(recursive: true);
    final archive = File('${voices.path}/$_name.tar.bz2');
    _cancel = CancelToken();
    try {
      try {
        await _download(archive, _cancel!);
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) return; // the owner cancelled
        debugPrint('Natural voice download failed: $e');
        rethrow;
      }
      await Isolate.run(() => _unpack(archive.path, voices.path));
      await File('${voices.path}/$_name/.ready').writeAsString('ok');
      installed.value = true;
      for (final old in _older) {
        final dir = Directory('${voices.path}/$old');
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Natural voice install failed: $e');
      rethrow;
    } finally {
      if (await archive.exists()) await archive.delete();
      progress.value = null;
      _cancel = null;
    }
  }

  /// Downloads the archive into [file], resuming from where a dropped
  /// connection left off rather than starting again.
  Future<void> _download(File file, CancelToken cancel) async {
    const attempts = 5;
    final dio = Dio();
    for (var attempt = 1; ; attempt++) {
      final have = await file.exists() ? await file.length() : 0;
      try {
        final response = await dio.get<ResponseBody>(
          _url,
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

  Future<void> remove() async {
    final dir = Directory('${(await _voicesDir()).path}/$_name');
    if (await dir.exists()) await dir.delete(recursive: true);
    installed.value = false;
  }

  /// bzip2 to a temporary tar beside it, then the tar onto disk, streamed so
  /// the 160 MB never sits in memory.
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

/// Whether the owner's accent is spoken the British way. Kokoro has American
/// and British English; Indian goes American, Australian and Irish British.
bool kokoroBritish(VoicePreference pref) => switch (pref.accent) {
  EchoAccent.us || EchoAccent.india => false,
  EchoAccent.uk || EchoAccent.australia || EchoAccent.ireland => true,
};

/// The Kokoro speaker for the owner's chosen voice: four in each accent.
int kokoroSpeaker(VoicePreference pref) {
  const american = [3, 2, 16, 11]; // af_heart, af_bella, am_michael, am_adam
  const british = [21, 22, 26, 25]; // bf_emma, bf_isabella, bm_george, bm_fable
  return (kokoroBritish(pref) ? british : american)[pref.voice.voiceIndex];
}

/// The speed slider (0..1, centre is normal) as Kokoro's speed.
double kokoroSpeed(VoicePreference pref) =>
    0.85 + 0.35 * pref.speed.clamp(0.0, 1.0);
