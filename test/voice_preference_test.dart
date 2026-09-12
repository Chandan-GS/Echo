import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/features/onboarding/data/voice_preference.dart';

void main() {
  group('EchoVoiceSlot', () {
    test('id round-trips through echoVoiceSlotFromId', () {
      for (final v in EchoVoiceSlot.values) {
        expect(echoVoiceSlotFromId(v.id), v);
      }
    });

    test('unknown / null ids fall back to aria', () {
      expect(echoVoiceSlotFromId(null), EchoVoiceSlot.aria);
      expect(echoVoiceSlotFromId('nonsense'), EchoVoiceSlot.aria);
      expect(echoVoiceSlotFromId(''), EchoVoiceSlot.aria);
    });

    test('every voice has a distinct label, index, and non-empty preview line',
        () {
      final labels = EchoVoiceSlot.values.map((v) => v.label).toSet();
      final indices = EchoVoiceSlot.values.map((v) => v.voiceIndex).toSet();
      expect(labels.length, EchoVoiceSlot.values.length);
      expect(indices.length, EchoVoiceSlot.values.length);
      for (final v in EchoVoiceSlot.values) {
        expect(v.previewLine.trim(), isNotEmpty);
      }
    });
  });

  group('EchoAccent', () {
    test('id round-trips through echoAccentFromId', () {
      for (final a in EchoAccent.values) {
        expect(echoAccentFromId(a.id), a);
      }
    });

    test('unknown / null ids fall back to us', () {
      expect(echoAccentFromId(null), EchoAccent.us);
      expect(echoAccentFromId('nonsense'), EchoAccent.us);
    });

    test('every accent has a valid en-* locale prefix', () {
      for (final a in EchoAccent.values) {
        expect(a.localePrefix, startsWith('en-'));
      }
    });
  });

  group('VoicePreference', () {
    test('copyWith overrides only the given fields', () {
      const base = VoicePreference(
        voice: EchoVoiceSlot.aria,
        accent: EchoAccent.us,
        speed: 0.5,
      );
      final next = base.copyWith(voice: EchoVoiceSlot.nova);
      expect(next.voice, EchoVoiceSlot.nova);
      expect(next.accent, EchoAccent.us);
      expect(next.speed, 0.5);
    });

    test('previewLine matches the selected voice', () {
      const pref = VoicePreference(
        voice: EchoVoiceSlot.atlas,
        accent: EchoAccent.uk,
        speed: 0.5,
      );
      expect(pref.previewLine, EchoVoiceSlot.atlas.previewLine);
    });
  });
}
