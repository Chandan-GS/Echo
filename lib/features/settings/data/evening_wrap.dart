import 'package:project_echo/features/echo/data/wrap/evening_wrap.dart';
import 'package:project_echo/features/onboarding/data/onboarding_personalization.dart';

/// The wrap notification's words.
class EveningWrapText {
  final String title;
  final String body;
  const EveningWrapText(this.title, this.body);
}

/// [wrap] as a notification, so it says what the wrap screen says: the same
/// sentences, without the spoken hello and goodbye or the bold markers. Only
/// the title follows the tone; the sentences belong to the composer.
EveningWrapText wrapNotificationText(EveningWrap wrap, OnboardingTone tone) {
  final sentences = wrap.clear || wrap.sentences.length < 3
      ? wrap.sentences
      : wrap.sentences.sublist(1, wrap.sentences.length - 1);
  return EveningWrapText(switch (tone) {
    OnboardingTone.professional => 'Your evening summary',
    OnboardingTone.friendly => 'Your evening wrap',
    OnboardingTone.direct => 'Evening wrap',
  }, sentences.join(' ').replaceAll('**', ''));
}
