import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/core/services/analytics_service.dart';
import 'package:project_echo/core/services/streak_service.dart';
import 'package:project_echo/features/onboarding/data/first_look.dart';
import 'package:project_echo/features/onboarding/data/onboarding_personalization.dart';
import 'package:project_echo/features/onboarding/data/voice_preference.dart';
import 'package:project_echo/features/onboarding/presentation/cubit/on_boarding_cubit.dart';
import 'package:project_echo/features/onboarding/presentation/screens/first_look_screen.dart';
import 'package:project_echo/features/onboarding/presentation/screens/streak_goal_screen.dart';
import 'package:project_echo/features/onboarding/presentation/widgets/access_preview.dart';
import 'package:project_echo/features/onboarding/presentation/widgets/onboarding_scaffold.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Events sent to the funnel, as "name" or "name {props}".
final sent = <String>[];

String describe(String event, Map<String, dynamic>? props) =>
    props == null || props.isEmpty ? event : '$event $props';

/// The phone's flow, at the step after naming.
Future<OnBoardingCubit> atName() async {
  final cubit = OnBoardingCubit(android: true, desktop: false);
  cubit.goBackToName();
  await Future<void>.delayed(Duration.zero);
  return cubit;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sent.clear();
    Analytics.debugSink = (e, p) => sent.add(describe(e, p));
  });
  tearDown(() => Analytics.debugSink = null);

  group('onboarding funnel', () {
    test('the phone’s first look comes straight after access', () async {
      final cubit = OnBoardingCubit(android: true, desktop: false);
      expect(sent, ['onboarding_step {step: welcome}']);

      cubit.completePermissions();
      expect(cubit.state, isA<FirstLookStep>());
      expect((cubit.state as FirstLookStep).autoPlay, isTrue);

      cubit.firstLookHeard(FirstLookKind.normal);
      cubit.firstLookHeard(FirstLookKind.normal); // counted once
      cubit.completeFirstLook();
      expect(cubit.state, isA<AppsStep>());

      // Back to the first look: it isn't read again by itself.
      cubit.goBackToFirstLook();
      expect((cubit.state as FirstLookStep).autoPlay, isFalse);

      expect(sent, [
        'onboarding_step {step: welcome}',
        'onboarding_step {step: first_look}',
        'onboarding_first_look_heard {kind: normal}',
        'onboarding_step {step: apps}',
        'onboarding_step {step: first_look, back: true}',
      ]);
    });

    test('one event per step reached, through to done', () async {
      final cubit = OnBoardingCubit(android: true, desktop: false);
      cubit.completePermissions();
      cubit.completeFirstLook();
      cubit.completeApps();
      cubit.completeAiMode();
      await cubit.saveUserNameAndContinue('Chandan');
      await cubit.completePersonalize(
        tone: OnboardingTone.friendly,
        interests: {OnboardingInterest.work},
      );
      await cubit.completeVoice(VoicePreference.fallback);
      await cubit.completePreview();
      expect(cubit.state, isA<StreakGoalStep>());
      await cubit.finishOnboarding();
      expect(cubit.state, isA<OnBoardingFinished>());

      expect(sent, [
        'onboarding_step {step: welcome}',
        'onboarding_step {step: first_look}',
        'onboarding_step {step: apps}',
        'onboarding_step {step: engine}',
        'onboarding_step {step: name}',
        'onboarding_step {step: personalise}',
        'onboarding_step {step: voice}',
        'onboarding_step {step: preview}',
        'onboarding_step {step: streak_goal}',
        'onboarding_completed {skipped: 0}',
      ]);
      // Never a name or anything Echo read.
      expect(sent.join(' '), isNot(contains('Chandan')));
    });

    test('skipping name, personalising and voice uses the defaults', () async {
      final cubit = await atName();
      sent.clear();

      cubit.skipName();
      expect(cubit.state, isA<PersonalizeStep>());
      await cubit.skipPersonalize();
      final voice = cubit.state as VoiceStep;
      expect(voice.name, '');
      expect(voice.tone, OnboardingTone.professional);
      expect(voice.interests, isEmpty);

      // The phone skips the preview with the voice, straight to the goal.
      await cubit.skipVoice();
      expect(cubit.state, isA<StreakGoalStep>());

      // Back from the goal returns to the voice step it was skipped from.
      cubit.goBackFromStreakGoal();
      expect(cubit.state, same(voice));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('user_name'), isNull);
      expect(prefs.getString('briefing_tone'), isNull);

      await cubit.skipVoice();
      await cubit.finishOnboarding();
      expect(sent, [
        'onboarding_step_skipped {step: name}',
        'onboarding_step {step: personalise}',
        'onboarding_step_skipped {step: personalise}',
        'onboarding_step {step: voice}',
        'onboarding_step_skipped {step: voice}',
        'onboarding_step {step: streak_goal}',
        'onboarding_step {step: voice, back: true}',
        'onboarding_step_skipped {step: voice}',
        'onboarding_step {step: streak_goal}',
        'onboarding_completed {skipped: 4}',
      ]);
    });

    test('a skipped step keeps what was chosen before', () async {
      SharedPreferences.setMockInitialValues({
        'user_name': 'Asha',
        'briefing_tone': 'direct',
        'briefing_interests': ['family'],
      });
      final cubit = await atName();
      cubit.skipName();
      await cubit.skipPersonalize();
      final voice = cubit.state as VoiceStep;
      expect(voice.name, 'Asha');
      expect(voice.tone, OnboardingTone.direct);
      expect(voice.interests, {OnboardingInterest.family});
    });

    test('back from the goal returns to the preview it came from', () async {
      final cubit = await atName();
      await cubit.saveUserNameAndContinue('Asha');
      await cubit.completePersonalize(
        tone: OnboardingTone.friendly,
        interests: const {},
      );
      await cubit.completeVoice(VoicePreference.fallback);
      final preview = cubit.state;
      await cubit.completePreview();
      cubit.goBackFromStreakGoal();
      expect(cubit.state, same(preview));
    });

    test('elsewhere the preview finishes, and skipping the voice previews '
        'the default', () async {
      final cubit = OnBoardingCubit(android: false, desktop: false);
      cubit.goBackToName();
      cubit.skipName();
      await cubit.skipPersonalize();
      await cubit.skipVoice();
      expect(cubit.state, isA<PreviewStep>());
      await cubit.completePreview();
      expect(cubit.state, isA<OnBoardingFinished>());
    });

    test('the first briefing heard is sent once, ever', () async {
      await StreakService().recordHeard();
      await StreakService().recordHeard();
      expect(sent, ['first_morning_briefing_heard']);

      sent.clear();
      SharedPreferences.setMockInitialValues({'briefings_heard_total': 4});
      await StreakService().recordHeard();
      expect(sent, isEmpty);
    });
  });

  group('onboarding screens', () {
    testWidgets('Skip shows on a skippable step and skips it', (tester) async {
      var skipped = 0;
      Widget shell({VoidCallback? onSkip}) => MaterialApp(
        home: OnboardingShell(
          step: 5,
          onBack: () {},
          onSkip: onSkip,
          body: const SizedBox(),
        ),
      );

      await tester.pumpWidget(shell());
      expect(find.text('Skip'), findsNothing);

      await tester.pumpWidget(shell(onSkip: () => skipped++));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Skip this step'), findsOneWidget);
      final size = tester.getSize(find.byType(TextButton));
      expect(size.height, greaterThanOrEqualTo(48));
      await tester.tap(find.text('Skip'));
      expect(skipped, 1);
    });

    testWidgets('the streak goal shows the week ahead and finishes', (
      tester,
    ) async {
      final cubit = OnBoardingCubit(android: true, desktop: false);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: BlocProvider.value(
                value: cubit,
                child: const StreakGoalScreen(),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Three mornings this week.'), findsOneWidget);
      expect(find.text('0 of 3 mornings'), findsOneWidget);
      // No launcher to pin to in tests: no widget offer.
      expect(find.text('Add to home screen'), findsNothing);

      await tester.tap(find.text('I’m in'));
      await tester.pump();
      expect(cubit.state, isA<OnBoardingFinished>());
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });

  testWidgets('the first look listens, then shows what Echo found', (
    tester,
  ) async {
    final cubit = OnBoardingCubit(android: true, desktop: false);
    cubit.completePermissions();
    final look = buildFirstLook(
      entries: const [],
      now: DateTime(2026, 11, 26, 18),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: BlocProvider.value(
              value: cubit,
              child: FirstLookScreen(autoPlay: false, load: () async => look),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Taking a first look…'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('All quiet, for now.'), findsOneWidget);
    expect(find.text(look.text), findsOneWidget);
    expect(find.bySemanticsLabel('Hear the first look again'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(cubit.state, isA<AppsStep>());
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the access sample plays, or shows its end with animations off', (
    tester,
  ) async {
    Widget preview({required bool still}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: still),
        child: const Scaffold(body: AccessPreview()),
      ),
    );
    Color? wordColor(String word) {
      final rich = tester.widget<RichText>(
        find.byWidgetPredicate(
          (w) =>
              w is RichText && w.text.toPlainText().contains('standup moved'),
        ),
      );
      Color? found;
      rich.text.visitChildren((span) {
        if (span is TextSpan && span.text == '$word ') {
          found = span.style?.color;
        }
        return found == null;
      });
      return found;
    }

    await tester.pumpWidget(preview(still: false));
    await tester.pump();
    expect(wordColor('Rahul’s'), Colors.transparent);
    await tester.pump(const Duration(seconds: 5));
    expect(wordColor('Rahul’s'), isNot(Colors.transparent));
    expect(
      find.bySemanticsLabel(RegExp('A sample of what Echo reads you')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(preview(still: true));
    await tester.pump();
    await tester.pump();
    expect(wordColor('Rahul’s'), isNot(Colors.transparent));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  test('the goal week starts at the first briefing', () {
    final evening = goalWeek(DateTime(2026, 11, 26, 18), '07:00');
    expect(evening.first, DateTime(2026, 11, 27));
    expect(evening, hasLength(7));
    final dawn = goalWeek(DateTime(2026, 11, 26, 5), '07:00');
    expect(dawn.first, DateTime(2026, 11, 26));
  });
}
