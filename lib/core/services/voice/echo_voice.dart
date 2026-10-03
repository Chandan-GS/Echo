import 'dart:async';
import 'dart:collection';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:project_echo/core/services/echo_tts.dart';
import 'package:project_echo/core/services/voice/piper_engine.dart';
import 'package:project_echo/core/services/voice/natural_voice.dart';
import 'package:project_echo/features/onboarding/data/voice_preference.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Echo's speaking voice: the natural on-device voice when it's downloaded,
/// the phone's own voice otherwise.
///
/// Sentences queue up and play back to back. The natural voice prepares the
/// next sentence while the current one plays, so there's no gap between them.
class EchoVoice {
  EchoVoice._();
  static final instance = EchoVoice._();

  /// The sentence being spoken, or null when quiet.
  final speaking = ValueNotifier<String?>(null);

  final _queue = Queue<String>();
  Completer<void>? _finished;
  Completer<void>? _cut;
  var _session = 0;

  PiperEngine? _piper;

  /// The voice folder [_piper] was started with.
  String? _piperDir;
  final _player = AudioPlayer();
  FlutterTts? _tts;

  /// Completes when everything queued has been said (or [stop] was called).
  Future<void> get finished => _finished?.future ?? Future.value();

  bool get isSpeaking => _finished != null;

  /// Loads the natural voice ahead of time (it takes a few seconds), so the
  /// first sentence isn't kept waiting. Screens that may speak call this
  /// when they open; it does nothing if the voice isn't downloaded.
  Future<void> warmUp() async {
    await _naturalEngine(
      VoicePreference.read(await SharedPreferences.getInstance()),
    );
  }

  /// Queues [sentence] to be said after whatever is already queued.
  void say(String sentence) {
    final text = sentence.trim();
    if (text.isEmpty) return;
    _queue.add(text);
    if (_finished == null) {
      _finished = Completer<void>();
      unawaited(_run(_session));
    }
  }

  /// Says [text] a sentence at a time.
  void sayAll(String text) {
    for (final s in splitSentences(text)) {
      say(s);
    }
  }

  Future<void> stop() async {
    _session++;
    _queue.clear();
    _cut?.complete();
    _cut = null;
    await _player.stop();
    await _tts?.stop();
    _done();
  }

  Future<void> _run(int session) async {
    final pref = VoicePreference.read(await SharedPreferences.getInstance());
    final piper = await _naturalEngine(pref);
    debugPrint('Echo voice: ${piper != null ? 'natural (Piper)' : 'phone'}');
    Future<Speech>? next;
    try {
      while (_queue.isNotEmpty && session == _session) {
        final sentence = _queue.removeFirst();
        if (piper != null) {
          final current =
              next ?? piper.speak(sentence, speed: piperSpeed(pref));
          final speech = await current;
          next = _queue.isEmpty
              ? null
              : piper.speak(_queue.first, speed: piperSpeed(pref));
          if (session != _session) break;
          speaking.value = sentence;
          await _play(speech, session);
        } else {
          speaking.value = sentence;
          await _speakWithPhone(sentence, session);
        }
      }
    } catch (e) {
      debugPrint('Echo stopped speaking: $e');
    }
    if (session == _session) _done();
  }

  void _done() {
    speaking.value = null;
    _finished?.complete();
    _finished = null;
  }

  /// The natural voice's engine, started on first use; null when the voice
  /// isn't downloaded or won't start.
  Future<PiperEngine?>? _starting;

  /// Starting it is shared, so a warm-up and a first sentence arriving
  /// together load it once.
  Future<PiperEngine?> _naturalEngine(VoicePreference pref) =>
      _starting ??= _startNatural(pref).whenComplete(() => _starting = null);

  Future<PiperEngine?> _startNatural(VoicePreference pref) async {
    final dir = await NaturalVoice.instance.modelDir(pref);
    if (dir == null) {
      _piper?.dispose();
      _piper = null;
      return null;
    }
    if (_piper != null && _piperDir == dir) return _piper;
    _piper?.dispose();
    try {
      _piper = await PiperEngine.start(dir, piperVoice(pref));
      _piperDir = dir;
    } catch (e) {
      debugPrint('Natural voice unavailable, using the phone voice: $e');
      _piper = null;
    }
    return _piper;
  }

  Future<void> _play(Speech speech, int session) async {
    final ended = _player.onPlayerComplete.first;
    final cut = _cut = Completer<void>();
    await _player.play(BytesSource(wav(speech), mimeType: 'audio/wav'));
    // A stop() mid-sentence never completes the player; it cuts instead.
    await Future.any([ended, cut.future]);
  }

  Future<void> _speakWithPhone(String sentence, int session) async {
    final tts = _tts ??= FlutterTts();
    await EchoTts.applyVoicePreferences(tts);
    await tts.awaitSpeakCompletion(true);
    if (session == _session) await tts.speak(sentence);
  }
}

/// [speech] as a 16-bit mono WAV file.
Uint8List wav(Speech speech) {
  final n = speech.samples.length;
  final out = ByteData(44 + n * 2);
  void ascii(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      out.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  out.setUint32(4, 36 + n * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  out.setUint32(16, 16, Endian.little);
  out.setUint16(20, 1, Endian.little); // PCM
  out.setUint16(22, 1, Endian.little); // mono
  out.setUint32(24, speech.sampleRate, Endian.little);
  out.setUint32(28, speech.sampleRate * 2, Endian.little);
  out.setUint16(32, 2, Endian.little);
  out.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  out.setUint32(40, n * 2, Endian.little);
  for (var i = 0; i < n; i++) {
    final v = (speech.samples[i].clamp(-1.0, 1.0) * 32767).round();
    out.setInt16(44 + i * 2, v, Endian.little);
  }
  return out.buffer.asUint8List();
}

/// [text] split into sentences for speaking one at a time. A full stop only
/// ends a sentence before a space or the end, so "7.30" stays whole.
List<String> splitSentences(String text) => [
  for (final m in RegExp(
    r'.+?(?:[.!?]+(?=\s|$)|$)',
    dotAll: true,
  ).allMatches(text))
    if (m[0]!.trim().isNotEmpty) m[0]!.trim(),
];
