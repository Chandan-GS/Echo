// Echo's voice model: four named, unisex voices (Aria, Sage, Atlas, Nova),
// each of which can speak in any available accent.
//
// A TTS "voice" is always a specific speaker tied to one accent, so we model a
// chosen voice as a (voice-slot × accent) pair: the slot picks one of four
// distinct device speakers, the accent picks the locale, and [VoiceCatalog]
// resolves the pair to a concrete device voice.
//
// Dependency-free so it can be unit-tested and reused by onboarding, Settings
// and the real briefing playback.

import 'package:shared_preferences/shared_preferences.dart';

/// The four selectable Echo voices. [voiceIndex] selects a distinct device
/// speaker within an accent, so the four voices sound different from each other.
enum EchoVoiceSlot { aria, sage, atlas, nova }

extension EchoVoiceSlotX on EchoVoiceSlot {
  String get id => name;

  String get label => switch (this) {
        EchoVoiceSlot.aria => 'Aria',
        EchoVoiceSlot.sage => 'Sage',
        EchoVoiceSlot.atlas => 'Atlas',
        EchoVoiceSlot.nova => 'Nova',
      };

  /// Which distinct device voice (0-based) this slot maps to within an accent.
  int get voiceIndex => switch (this) {
        EchoVoiceSlot.aria => 0,
        EchoVoiceSlot.sage => 1,
        EchoVoiceSlot.atlas => 2,
        EchoVoiceSlot.nova => 3,
      };

  String get previewLine => switch (this) {
        EchoVoiceSlot.aria =>
          "Hi, I'm Aria. I'll keep your mornings calm and clear.",
        EchoVoiceSlot.sage =>
          "I'm Sage. Let's take your day one step at a time.",
        EchoVoiceSlot.atlas =>
          "Atlas here. Let's get you briefed and ready to move.",
        EchoVoiceSlot.nova =>
          "Hey, I'm Nova — here's everything you need this morning.",
      };
}

EchoVoiceSlot echoVoiceSlotFromId(String? id) => switch (id) {
      'sage' => EchoVoiceSlot.sage,
      'atlas' => EchoVoiceSlot.atlas,
      'nova' => EchoVoiceSlot.nova,
      _ => EchoVoiceSlot.aria,
    };

/// A spoken English accent. [localePrefix] is what we hand to flutter_tts.
enum EchoAccent { us, uk, australia, india, ireland }

extension EchoAccentX on EchoAccent {
  String get id => name;

  String get localePrefix => switch (this) {
        EchoAccent.us => 'en-US',
        EchoAccent.uk => 'en-GB',
        EchoAccent.australia => 'en-AU',
        EchoAccent.india => 'en-IN',
        EchoAccent.ireland => 'en-IE',
      };

  String get label => switch (this) {
        EchoAccent.us => 'American',
        EchoAccent.uk => 'British',
        EchoAccent.australia => 'Australian',
        EchoAccent.india => 'Indian',
        EchoAccent.ireland => 'Irish',
      };

  String get short => switch (this) {
        EchoAccent.us => 'US',
        EchoAccent.uk => 'UK',
        EchoAccent.australia => 'AU',
        EchoAccent.india => 'IN',
        EchoAccent.ireland => 'IE',
      };
}

EchoAccent echoAccentFromId(String? id) => switch (id) {
      'uk' => EchoAccent.uk,
      'australia' => EchoAccent.australia,
      'india' => EchoAccent.india,
      'ireland' => EchoAccent.ireland,
      _ => EchoAccent.us,
    };

/// A chosen voice: which speaker, which accent, and how fast. [speed] is a 0..1
/// slider value (0.5 = a natural narration pace) mapped to a rate by the TTS
/// layer.
///
/// Desktop bypasses the slot × accent abstraction entirely — it has a real,
/// named system voice list (whatever's installed via System Settings), so
/// [directVoiceName]/[directVoiceLocale], when set, name a specific device
/// voice directly and take priority over [voice]/[accent]. Phone never sets
/// these; desktop always does once a voice has been resolved.
class VoicePreference {
  final EchoVoiceSlot voice;
  final EchoAccent accent;
  final double speed;
  final String? directVoiceName;
  final String? directVoiceLocale;

  const VoicePreference({
    required this.voice,
    required this.accent,
    required this.speed,
    this.directVoiceName,
    this.directVoiceLocale,
  });

  static const VoicePreference fallback = VoicePreference(
    voice: EchoVoiceSlot.aria,
    accent: EchoAccent.us,
    speed: 0.5,
  );

  bool get hasDirectVoice => directVoiceName != null && directVoiceLocale != null;

  VoicePreference copyWith({
    EchoVoiceSlot? voice,
    EchoAccent? accent,
    double? speed,
  }) {
    return VoicePreference(
      voice: voice ?? this.voice,
      accent: accent ?? this.accent,
      speed: speed ?? this.speed,
      directVoiceName: directVoiceName,
      directVoiceLocale: directVoiceLocale,
    );
  }

  /// Desktop only — picks a specific installed device voice by name, bypassing
  /// the slot/accent abstraction.
  VoicePreference withDirectVoice({required String name, required String locale}) {
    return VoicePreference(
      voice: voice,
      accent: accent,
      speed: speed,
      directVoiceName: name,
      directVoiceLocale: locale,
    );
  }

  static const _directPreviewLine =
      "Hi, this is how Echo will sound in your morning briefing.";

  String get previewLine => hasDirectVoice ? _directPreviewLine : voice.previewLine;

  static const _kSlot = 'briefing_voice_slot';
  static const _kAccent = 'briefing_voice_accent';
  static const _kSpeed = 'speech_rate';
  static const _kDirectName = 'briefing_voice_direct_name';
  static const _kDirectLocale = 'briefing_voice_direct_locale';

  Future<void> persist(SharedPreferences prefs) async {
    await prefs.setString(_kSlot, voice.id);
    await prefs.setString(_kAccent, accent.id);
    await prefs.setDouble(_kSpeed, speed);
    if (hasDirectVoice) {
      await prefs.setString(_kDirectName, directVoiceName!);
      await prefs.setString(_kDirectLocale, directVoiceLocale!);
    } else {
      await prefs.remove(_kDirectName);
      await prefs.remove(_kDirectLocale);
    }
  }

  /// Reads the persisted preference, migrating older layouts (the interim
  /// gender model and the original single-persona key) so users keep their voice.
  static VoicePreference read(SharedPreferences prefs) {
    final speed = prefs.getDouble(_kSpeed) ?? 0.5;
    final directName = prefs.getString(_kDirectName);
    final directLocale = prefs.getString(_kDirectLocale);

    final slot = prefs.getString(_kSlot);
    if (slot != null) {
      return VoicePreference(
        voice: echoVoiceSlotFromId(slot),
        accent: echoAccentFromId(prefs.getString(_kAccent)),
        speed: speed,
        directVoiceName: directName,
        directVoiceLocale: directLocale,
      );
    }

    // Migrate the original single persona key (same names).
    final legacy = prefs.getString('briefing_voice');
    if (legacy != null) {
      return VoicePreference(
        voice: echoVoiceSlotFromId(legacy),
        accent: echoAccentFromId(prefs.getString('briefing_voice_accent')),
        speed: speed,
        directVoiceName: directName,
        directVoiceLocale: directLocale,
      );
    }

    return fallback.copyWith(speed: speed);
  }
}
