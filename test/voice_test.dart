import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/core/services/voice/echo_voice.dart';
import 'package:project_echo/core/services/voice/piper_engine.dart';
import 'package:project_echo/core/services/voice/natural_voice.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/reading_echo.dart';
import 'package:project_echo/features/onboarding/data/voice_preference.dart';

void main() {
  test('speech is split into sentences, keeping times like 7.30 whole', () {
    expect(
      splitSentences(
        'Three things before the 7.30 demo. Neha needs the deck! And you?',
      ),
      [
        'Three things before the 7.30 demo.',
        'Neha needs the deck!',
        'And you?',
      ],
    );
    expect(splitSentences('No full stop at the end'), [
      'No full stop at the end',
    ]);
  });

  test('a sentence becomes a 16-bit mono WAV', () {
    final bytes = wav(Speech(Float32List.fromList([0, 1, -1, 0.5]), 24000));
    final data = ByteData.sublistView(bytes);
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
    expect(data.getUint32(24, Endian.little), 24000);
    expect(data.getUint32(40, Endian.little), 8);
    expect(data.getInt16(46, Endian.little), 32767);
    expect(data.getInt16(48, Endian.little), -32767);
  });

  test('each voice and accent has its own Piper voice', () {
    VoicePreference pref(EchoVoiceSlot v, EchoAccent a) =>
        VoicePreference.fallback.copyWith(voice: v, accent: a);
    final american = {
      for (final v in EchoVoiceSlot.values) piperVoice(pref(v, EchoAccent.us)),
    };
    final british = {
      for (final v in EchoVoiceSlot.values) piperVoice(pref(v, EchoAccent.uk)),
    };
    expect(american, hasLength(4));
    expect(british, hasLength(4));
    expect(american.every((v) => v.startsWith('en_US-')), isTrue);
    expect(british.every((v) => v.startsWith('en_GB-')), isTrue);
    expect(
      piperVoice(pref(EchoVoiceSlot.aria, EchoAccent.india)),
      'en_US-lessac-medium',
    );
    expect(
      piperSpeed(VoicePreference.fallback.copyWith(speed: 0.5)),
      closeTo(1.025, 1e-9),
    );
  });

  test('reading: across a line, back, and down', () {
    expect(readingGaze(Duration.zero).dx, closeTo(-0.85, 1e-9));
    expect(readingGaze(const Duration(milliseconds: 719)).dx, greaterThan(0.8));
    expect(
      readingGaze(const Duration(milliseconds: 900)).dy,
      closeTo(0.4, 1e-9),
    );
  });
}
