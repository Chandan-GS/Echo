import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/features/onboarding/data/onboarding_personalization.dart';

void main() {
  group('OnboardingTone', () {
    test('id round-trips through onboardingToneFromId', () {
      for (final t in OnboardingTone.values) {
        expect(onboardingToneFromId(t.id), t);
      }
    });

    test('defaults to professional for unknown/null ids', () {
      expect(onboardingToneFromId(null), OnboardingTone.professional);
      expect(onboardingToneFromId('garbage'), OnboardingTone.professional);
      expect(onboardingToneFromId(''), OnboardingTone.professional);
    });

    test('every tone has non-empty label, description and prompt instruction',
        () {
      for (final t in OnboardingTone.values) {
        expect(t.label, isNotEmpty);
        expect(t.description, isNotEmpty);
        expect(t.promptInstruction, isNotEmpty);
      }
    });
  });

  group('OnboardingInterest', () {
    test('id round-trips', () {
      for (final i in OnboardingInterest.values) {
        expect(onboardingInterestFromId(i.id), i);
      }
    });

    test('unknown id returns null', () {
      expect(onboardingInterestFromId('nope'), isNull);
    });
  });

  group('buildSampleBriefing', () {
    test('includes the user name', () {
      final s = buildSampleBriefing(
        name: 'Ada',
        tone: OnboardingTone.professional,
        interests: {OnboardingInterest.work},
      );
      expect(s, contains('Ada'));
    });

    test('falls back to "there" for an empty name', () {
      final s = buildSampleBriefing(
        name: '   ',
        tone: OnboardingTone.professional,
        interests: {},
      );
      expect(s, contains('there'));
    });

    test('mentions each selected interest', () {
      final s = buildSampleBriefing(
        name: 'Ada',
        tone: OnboardingTone.friendly,
        interests: {
          OnboardingInterest.work,
          OnboardingInterest.health,
          OnboardingInterest.deliveries,
        },
      );
      expect(s, contains('standup')); // work
      expect(s, contains('dentist')); // health
      expect(s, contains('Swiggy')); // deliveries
    });

    test('uses sensible default topics when no interests are chosen', () {
      final s = buildSampleBriefing(
        name: 'Ada',
        tone: OnboardingTone.professional,
        interests: {},
      );
      expect(s, contains('standup')); // work (default)
      expect(s, contains('Swiggy')); // deliveries (default)
    });

    test('tone changes the opening', () {
      final pro = buildSampleBriefing(
        name: 'Ada',
        tone: OnboardingTone.professional,
        interests: {OnboardingInterest.work},
      );
      final direct = buildSampleBriefing(
        name: 'Ada',
        tone: OnboardingTone.direct,
        interests: {OnboardingInterest.work},
      );
      expect(pro, startsWith('Good morning, Ada.'));
      expect(direct, startsWith('Ada, here is your day.'));
      expect(pro, isNot(equals(direct)));
    });

    test('joins multiple interests naturally with "and"', () {
      final s = buildSampleBriefing(
        name: 'Ada',
        tone: OnboardingTone.professional,
        interests: {OnboardingInterest.work, OnboardingInterest.family},
      );
      expect(s, contains(' and '));
    });

    test('never contains double spaces', () {
      for (final tone in OnboardingTone.values) {
        final s = buildSampleBriefing(
          name: 'Ada',
          tone: tone,
          interests: OnboardingInterest.values.toSet(),
        );
        expect(s.contains('  '), isFalse, reason: 'tone=$tone → "$s"');
      }
    });
  });
}
