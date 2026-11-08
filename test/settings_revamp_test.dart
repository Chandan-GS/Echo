import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/core/services/analytics_service.dart';
import 'package:project_echo/features/onboarding/data/onboarding_personalization.dart';
import 'package:project_echo/features/settings/data/engine_status.dart';
import 'package:project_echo/features/echo/data/wrap/evening_wrap.dart';
import 'package:project_echo/features/settings/data/evening_wrap.dart';
import 'package:project_echo/features/settings/data/schedule_prefs.dart';
import 'package:project_echo/features/settings/data/tone_voice.dart';
import 'package:project_echo/features/settings/data/writing_pack.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('engineInUse', () {
    test('cloud needs both the switch and a key', () {
      expect(
        engineInUse(isOffline: false, geminiKey: 'AIzaKey', packReady: false),
        EngineInUse.cloud,
      );
      expect(
        engineInUse(isOffline: false, geminiKey: '  ', packReady: true),
        EngineInUse.writingPack,
      );
      expect(
        engineInUse(isOffline: true, geminiKey: 'AIzaKey', packReady: true),
        EngineInUse.writingPack,
      );
    });

    test('nothing when there is neither', () {
      expect(
        engineInUse(isOffline: true, geminiKey: '', packReady: false),
        EngineInUse.none,
      );
    });

    test('summary names a paired computer first', () {
      final s = engineSummary(
        EngineInUse.writingPack,
        packName: 'Qwen2.5 1.5B',
        computerPaired: true,
      );
      expect(s, startsWith('Your computer'));
      expect(s, contains('Qwen2.5 1.5B on this phone'));
    });
  });

  group('maskApiKey', () {
    test('keeps only the ends', () {
      final masked = maskApiKey('AIzaSyD-1234567890abcdf3Xq');
      expect(masked, 'AIza…f3Xq');
      expect(masked, isNot(contains('1234567890')));
    });

    test('a short key is never shown', () {
      expect(maskApiKey('abc'), '••••');
    });
  });

  group('clock labels', () {
    test('format 24-hour times', () {
      expect(clockLabel('21:30'), '9:30 PM');
      expect(clockLabel('00:05'), '12:05 AM');
      expect(clockLabel('12:00'), '12:00 PM');
    });

    test('join times with "and"', () {
      expect(joinClockLabels(['07:00']), '7:00 AM');
      expect(joinClockLabels(['07:00', '19:00']), '7:00 AM and 7:00 PM');
      expect(
        joinClockLabels(['07:00', '12:30', '19:00']),
        '7:00 AM, 12:30 PM and 7:00 PM',
      );
    });

    test('a malformed stored wrap time falls back to the default', () {
      expect(eveningWrapTimeOrDefault('nonsense'), defaultEveningWrapTime);
      expect(eveningWrapTimeOrDefault(null), defaultEveningWrapTime);
      expect(eveningWrapTimeOrDefault('22:00'), '22:00');
    });
  });

  group('quietWhenLabel', () {
    test('names the common shapes', () {
      expect(quietWhenLabel({1, 2, 3, 4, 5}, 540, 780), 'Weekdays, 9 AM to 1 PM');
      expect(
        quietWhenLabel({1, 2, 3, 4, 5, 6, 7}, 1350, 420),
        'Every day, 10:30 PM to 7 AM',
      );
      expect(quietWhenLabel({6, 7}, 0, 720), 'Weekends, 12 AM to 12 PM');
      expect(quietWhenLabel({1, 3, 5}, 540, 600), '3 days a week, 9 AM to 10 AM');
    });
  });

  group('packSizeLabel', () {
    test('reads the real size', () {
      expect(packSizeLabel(950 * 1024 * 1024), '950 MB');
      expect(packSizeLabel((1.6 * 1024 * 1024 * 1024).round()), '1.6 GB');
    });
  });

  group('wrapNotificationText', () {
    const tone = OnboardingTone.friendly;

    test('says what the wrap says, without hello, goodbye or markers', () {
      final wrap = buildEveningWrap(
        const WrapInput(
          waiting: [WrapWaiting('Amma', 3), WrapWaiting('Rohan', 1)],
          tomorrowFirst: 'pay the electricity bill',
          tomorrowCount: 3,
        ),
      );
      final text = wrapNotificationText(wrap, tone);
      expect(
        text.body,
        'Two people are still waiting: Amma for three days, and Rohan since '
        'yesterday. Tomorrow: pay the electricity bill, and two more.',
      );
      expect(text.body, isNot(contains('**')));
      expect(text.body, isNot(contains('Sleep well')));
    });

    test('includes who owes an answer, and only when someone does', () {
      final owed = wrapNotificationText(
        buildEveningWrap(
          const WrapInput(
            waiting: [WrapWaiting('Amma', 1)],
            owed: [WrapOwed('Karan', 'the deck', 2)],
          ),
        ),
        tone,
      );
      expect(owed.body, contains('Karan still owes you an answer about the deck.'));

      final none = wrapNotificationText(
        buildEveningWrap(const WrapInput(waiting: [WrapWaiting('Amma', 1)])),
        tone,
      );
      expect(none.body, isNot(contains('owes you')));
    });

    test('a clear evening keeps its one sentence', () {
      final text = wrapNotificationText(
        buildEveningWrap(const WrapInput()),
        tone,
      );
      expect(text.body, startsWith('A clear evening.'));
    });

    test('the title follows the tone', () {
      final wrap = buildEveningWrap(const WrapInput());
      expect(
        wrapNotificationText(wrap, OnboardingTone.direct).title,
        'Evening wrap',
      );
      expect(
        wrapNotificationText(wrap, OnboardingTone.professional).title,
        'Your evening summary',
      );
    });
  });

  group('tone', () {
    test('holding replies follow it, with no emoji for professional', () {
      final professional = holdingReplies(OnboardingTone.professional);
      expect(professional, isNotEmpty);
      expect(professional.join(), isNot(contains('👍')));
      expect(
        holdingReplies(OnboardingTone.friendly),
        isNot(equals(professional)),
      );
    });

    test('every tone has draft guidance', () {
      for (final tone in OnboardingTone.values) {
        expect(toneDraftNote(tone), isNotEmpty);
      }
    });
  });

  group('SettingsCubit schedule settings', () {
    test('default to wrap on at 9:30 and the briefing on', () async {
      SharedPreferences.setMockInitialValues({});
      final cubit = SettingsCubit();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(cubit.state.eveningWrapEnabled, isTrue);
      expect(cubit.state.eveningWrapTime, '21:30');
      expect(cubit.state.briefingEnabled, isTrue);
      await cubit.close();
    });

    test('persist and emit', () async {
      SharedPreferences.setMockInitialValues({});
      final cubit = SettingsCubit();
      await cubit.setBriefingEnabled(false);
      await cubit.setEveningWrapTime('22:00');
      await cubit.setEveningWrapEnabled(false);
      expect(cubit.state.briefingEnabled, isFalse);
      expect(cubit.state.eveningWrapTime, '22:00');
      expect(cubit.state.eveningWrapEnabled, isFalse);
      await cubit.close();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(briefingEnabledKey), isFalse);
      expect(prefs.getString(eveningWrapTimeKey), '22:00');

      final reloaded = SettingsCubit();
      await reloaded.stream.firstWhere((s) => s.eveningWrapTime == '22:00');
      expect(reloaded.state.briefingEnabled, isFalse);
      await reloaded.close();
    });

    test('clearing the desktop host keeps the schedule settings', () async {
      SharedPreferences.setMockInitialValues({});
      final cubit = SettingsCubit();
      await cubit.setBriefingEnabled(false);
      await cubit.setEveningWrapTime('20:30');
      await cubit.setDesktopEngineHost(null);
      expect(cubit.state.briefingEnabled, isFalse);
      expect(cubit.state.eveningWrapTime, '20:30');
      await cubit.close();
    });

    test('cloud settings written by another screen show in the state', () async {
      SharedPreferences.setMockInitialValues({});
      await Analytics.setEnabled(false);
      final cubit = SettingsCubit();
      await cubit.setGeminiApiKey('AIzaKey');
      await cubit.setAiEngine(isOffline: false);
      expect(
        engineInUse(
          isOffline: cubit.state.isOfflineEngine,
          geminiKey: cubit.state.geminiApiKey,
          packReady: false,
        ),
        EngineInUse.cloud,
      );
      await cubit.close();
    });

    test('theme mode still round-trips', () async {
      SharedPreferences.setMockInitialValues({});
      final cubit = SettingsCubit();
      await cubit.setThemeMode(ThemeMode.dark);
      expect(cubit.state.themeMode, ThemeMode.dark);
      await cubit.close();
    });
  });
}
