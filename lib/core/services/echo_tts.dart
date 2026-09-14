import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_echo/core/services/voice_catalog.dart';
import 'package:project_echo/features/onboarding/data/voice_preference.dart';

/// Single place that turns the user's [VoicePreference] (gender · accent · pitch
/// · speed) into concrete flutter_tts configuration. Used by the onboarding
/// voice step, the Settings voice section, and the real briefing / Ask-Echo
/// playback so the voice shaped during setup is the voice heard everywhere.
class EchoTts {
  /// Reads the persisted preference (migrating legacy values) and applies it.
  static Future<void> applyVoicePreferences(FlutterTts tts) async {
    final prefs = await SharedPreferences.getInstance();
    await applyPreference(tts, VoicePreference.read(prefs));
  }

  /// Applies a specific [pref] — used live while the user is shaping their voice
  /// before it is persisted.
  static Future<void> applyPreference(
    FlutterTts tts,
    VoicePreference pref,
  ) async {
    try {
      if (pref.hasDirectVoice) {
        // Desktop: a specific installed device voice was chosen directly.
        await tts.setLanguage(pref.directVoiceLocale!);
        await tts.setVoice({
          'name': pref.directVoiceName!,
          'locale': pref.directVoiceLocale!,
        });
      } else {
        await tts.setLanguage(pref.accent.localePrefix);

        // Resolve the voice slot × accent to a distinct device speaker.
        final voice = await VoiceCatalog.instance.resolveVoice(tts, pref);
        if (voice != null) {
          await tts.setVoice(voice);
        }
      }

      // Natural pitch; set AFTER the voice so the engine can't reset it.
      await tts.setPitch(1.0);
      await tts.setSpeechRate(_rateForSpeed(pref.speed));
    } catch (_) {
      // TTS may be unavailable on some devices — callers still show transcripts.
    }
  }

  /// Maps the 0..1 speed slider onto a natural flutter_tts speech rate. 0.5
  /// (slider centre) lands on ~0.47, a comfortable narration pace.
  static double _rateForSpeed(double speed) {
    final s = speed.clamp(0.0, 1.0);
    return (0.32 + (0.62 - 0.32) * s).clamp(0.25, 1.0);
  }
}
