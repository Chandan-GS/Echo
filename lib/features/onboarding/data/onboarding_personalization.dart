// Personalization choices captured during onboarding. Kept as plain,
// dependency-free logic so it can be unit-tested and reused both to build the
// spoken onboarding preview and to steer the real briefing prompt.

/// How Echo should address and speak to the user.
enum OnboardingTone {
  /// Polished, formal — the "personal butler" voice.
  professional,

  /// Warm and casual, like a helpful friend.
  friendly,

  /// Terse, no filler — just the facts.
  direct,
}

extension OnboardingToneX on OnboardingTone {
  /// Stable string used for persistence (SharedPreferences).
  String get id => switch (this) {
        OnboardingTone.professional => 'professional',
        OnboardingTone.friendly => 'friendly',
        OnboardingTone.direct => 'direct',
      };

  /// Short user-facing label for selection cards.
  String get label => switch (this) {
        OnboardingTone.professional => 'Professional',
        OnboardingTone.friendly => 'Friendly',
        OnboardingTone.direct => 'Straight to the point',
      };

  /// One-line description shown under the label.
  String get description => switch (this) {
        OnboardingTone.professional =>
          'Polished and formal, like a personal butler.',
        OnboardingTone.friendly => 'Warm and casual, like a good friend.',
        OnboardingTone.direct => 'Just the facts. No small talk.',
      };

  /// Instruction appended to the real briefing system prompt so the chosen
  /// tone actually changes generated briefings (not just the preview).
  String get promptInstruction => switch (this) {
        OnboardingTone.professional =>
          'Adopt a polished, professional and warm butler-like tone.',
        OnboardingTone.friendly =>
          'Adopt a warm, casual, friendly tone as if speaking to a close friend.',
        OnboardingTone.direct =>
          'Be extremely concise and direct. Skip pleasantries and filler; state only the essential facts.',
      };
}

/// Parses a persisted tone id back into an [OnboardingTone], defaulting to
/// [OnboardingTone.professional] for unknown/legacy values.
OnboardingTone onboardingToneFromId(String? id) {
  return switch (id) {
    'friendly' => OnboardingTone.friendly,
    'direct' => OnboardingTone.direct,
    _ => OnboardingTone.professional,
  };
}

/// A topic the user cares about. Order here is the display order.
enum OnboardingInterest { work, family, finance, health, deliveries, news }

extension OnboardingInterestX on OnboardingInterest {
  String get id => name; // 'work', 'family', ...

  String get label => switch (this) {
        OnboardingInterest.work => 'Work',
        OnboardingInterest.family => 'Family',
        OnboardingInterest.finance => 'Finance',
        OnboardingInterest.health => 'Health',
        OnboardingInterest.deliveries => 'Deliveries',
        OnboardingInterest.news => 'News',
      };

  /// A believable sample sentence fragment used to build the preview briefing.
  String get _sampleFragment => switch (this) {
        OnboardingInterest.work =>
          'your 10 AM standup is still on and Priya shared the Figma links',
        OnboardingInterest.family =>
          'your mum asked if you are free for Sunday dinner',
        OnboardingInterest.finance =>
          'your account was credited 500 and a card bill is due Friday',
        OnboardingInterest.health =>
          'you have a dentist appointment at 4:30 PM',
        OnboardingInterest.deliveries =>
          'your Swiggy order is out for delivery',
        OnboardingInterest.news => 'and markets closed a little higher today',
      };
}

OnboardingInterest? onboardingInterestFromId(String id) {
  for (final i in OnboardingInterest.values) {
    if (i.id == id) return i;
  }
  return null;
}

/// Default preview topics when the user hasn't picked any interests yet.
const _defaultPreviewInterests = [
  OnboardingInterest.work,
  OnboardingInterest.deliveries,
];

/// Builds a short, personalized sample briefing used in the onboarding preview
/// (both the on-screen transcript and the on-device TTS voiceover).
///
/// It is deliberately scripted (not model-generated) so the "aha moment" works
/// instantly, offline, before any model is downloaded.
String buildSampleBriefing({
  required String name,
  required OnboardingTone tone,
  required Set<OnboardingInterest> interests,
}) {
  final safeName = name.trim().isEmpty ? 'there' : name.trim();

  // Preserve enum display order; fall back to sensible defaults.
  final selected = OnboardingInterest.values
      .where(interests.contains)
      .toList(growable: false);
  final topics = selected.isEmpty ? _defaultPreviewInterests : selected;

  final fragments = topics.map((t) => t._sampleFragment).toList();
  final body = _joinNaturally(fragments);

  final opening = switch (tone) {
    OnboardingTone.professional => 'Good morning, $safeName.',
    OnboardingTone.friendly => 'Morning, $safeName!',
    OnboardingTone.direct => '$safeName, here is your day.',
  };

  final lead = switch (tone) {
    OnboardingTone.professional => ' Looking at your day, ',
    OnboardingTone.friendly => " Here's what's up: ",
    OnboardingTone.direct => ' ',
  };

  final closing = switch (tone) {
    OnboardingTone.professional => ' A productive day ahead, $safeName.',
    OnboardingTone.friendly => " You've got this!",
    OnboardingTone.direct => '',
  };

  final sentence = '$opening$lead$body.$closing';
  // Normalize any accidental double spaces.
  return sentence.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Joins fragments into a natural clause: "a", "a and b", "a, b and c".
String _joinNaturally(List<String> parts) {
  if (parts.isEmpty) return '';
  if (parts.length == 1) return parts.first;
  final head = parts.sublist(0, parts.length - 1).join(', ');
  return '$head and ${parts.last}';
}
