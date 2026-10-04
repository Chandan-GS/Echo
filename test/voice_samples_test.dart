import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/core/services/voice/natural_voice.dart';
import 'package:project_echo/features/onboarding/data/voice_preference.dart';

void main() {
  test('every voice onboarding offers has a sample to hear', () {
    for (final voice in EchoVoiceSlot.values) {
      for (final accent in piperAccents) {
        final pref = VoicePreference.fallback.copyWith(
          voice: voice,
          accent: accent,
        );
        final asset = File('assets/${voiceSampleAsset(pref)}');
        expect(asset.existsSync(), isTrue, reason: asset.path);
      }
    }
  });

  test('other accents are heard in the natural voice nearest them', () {
    expect(piperAccent(EchoAccent.india), EchoAccent.us);
    expect(piperAccent(EchoAccent.australia), EchoAccent.uk);
    expect(piperAccent(EchoAccent.ireland), EchoAccent.uk);
  });

  test('a sample plays at normal speed at the slider centre', () {
    expect(voiceSampleRate(VoicePreference.fallback), 1.0);
    expect(
      voiceSampleRate(VoicePreference.fallback.copyWith(speed: 1)),
      greaterThan(1.0),
    );
  });
}
