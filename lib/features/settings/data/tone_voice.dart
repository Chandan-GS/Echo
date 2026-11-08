import 'package:project_echo/features/onboarding/data/onboarding_personalization.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The tone picked in Settings. Reloads first: the alarms run in their own
/// isolate, with their own copy of the prefs.
Future<OnboardingTone> currentTone() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  return onboardingToneFromId(prefs.getString('briefing_tone'));
}

/// Quick notes Echo offers so nobody's left on read, in the owner's tone.
/// A Professional Echo never offers a thumbs-up to someone's manager.
List<String> holdingReplies(OnboardingTone tone) => switch (tone) {
  OnboardingTone.professional => const [
    'Received. I’ll reply by this evening.',
    'Thank you. I’ll get back to you tomorrow morning.',
    'I’m tied up at the moment and will respond shortly.',
  ],
  OnboardingTone.friendly => const [
    'Saw this! Will reply properly tonight.',
    'On it, give me 10 min',
    'Give me till tomorrow morning?',
  ],
  OnboardingTone.direct => const [
    'Seen. Replying tonight.',
    'Busy now. Replying tomorrow.',
    'Will call back.',
  ],
};

/// Added to a reply draft's instruction so the draft sounds like the tone.
String toneDraftNote(OnboardingTone tone) => switch (tone) {
  OnboardingTone.professional =>
    'Keep the wording polished and courteous, with no slang or emoji.',
  OnboardingTone.friendly =>
    'Keep it warm and casual; an emoji is fine if the conversation already '
        'uses them.',
  OnboardingTone.direct =>
    'Keep it as short as it can be, with no pleasantries.',
};
