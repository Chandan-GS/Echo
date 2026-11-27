import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/core/utils/nudge_rules.dart';
import 'package:project_echo/features/echo/presentation/widgets/home_first_briefing.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('missedMorningsNudgeDue', () {
    // Installed well before; briefing at 07:00.
    final installed = DateTime(2026, 11, 1, 9);
    bool due({
      required DateTime now,
      Set<String> heard = const {},
      DateTime? firstLaunch,
      String? lastNudge,
      List<String> times = const ['07:00'],
    }) => missedMorningsNudgeDue(
      now: now,
      heardDates: heard,
      briefingTimes: times,
      firstLaunch: firstLaunch ?? installed,
      lastNudgeDate: lastNudge,
    );

    test('two unheard mornings in a row: due', () {
      expect(
        due(now: DateTime(2026, 11, 26, 7), heard: {'2026-11-23'}),
        isTrue,
      );
    });

    test('one unheard morning only: not due', () {
      expect(
        due(now: DateTime(2026, 11, 26, 7), heard: {'2026-11-24'}),
        isFalse,
      );
    });

    test('already heard today: not due', () {
      expect(
        due(now: DateTime(2026, 11, 26, 19), heard: {'2026-11-26'}),
        isFalse,
      );
    });

    test('never on the first days', () {
      // Installed yesterday evening: there's been no scheduled morning yet.
      expect(
        due(
          now: DateTime(2026, 11, 26, 7),
          firstLaunch: DateTime(2026, 11, 25, 18),
        ),
        isFalse,
      );
      // Installed the day before yesterday, after its 07:00: only one
      // scheduled morning has been missed.
      expect(
        due(
          now: DateTime(2026, 11, 26, 7),
          firstLaunch: DateTime(2026, 11, 24, 9),
        ),
        isFalse,
      );
      // Installed that morning before 07:00: both mornings count.
      expect(
        due(
          now: DateTime(2026, 11, 26, 7),
          firstLaunch: DateTime(2026, 11, 24, 6, 30),
        ),
        isTrue,
      );
    });

    test('unknown install day or no briefing times: not due', () {
      expect(
        missedMorningsNudgeDue(
          now: DateTime(2026, 11, 26, 7),
          heardDates: const {},
          briefingTimes: const ['07:00'],
          firstLaunch: null,
        ),
        isFalse,
      );
      expect(due(now: DateTime(2026, 11, 26, 7), times: const []), isFalse);
    });

    test('at most one nudge per lapse', () {
      // Nudged yesterday, still nothing heard: silence.
      expect(
        due(
          now: DateTime(2026, 11, 26, 7),
          heard: {'2026-11-20'},
          lastNudge: '2026-11-25',
        ),
        isFalse,
      );
      // Never heard at all, nudged once: silence for good.
      expect(
        due(now: DateTime(2026, 11, 30, 7), lastNudge: '2026-11-25'),
        isFalse,
      );
    });

    test('hearing one again starts a new lapse', () {
      // Nudged on the 20th, heard on the 21st, then two more mornings
      // missed (the 24th and 25th).
      expect(
        due(
          now: DateTime(2026, 11, 26, 7),
          heard: {'2026-11-21'},
          lastNudge: '2026-11-20',
        ),
        isTrue,
      );
      // Heard the day of the nudge itself also ends that lapse.
      expect(
        due(
          now: DateTime(2026, 11, 26, 7),
          heard: {'2026-11-20'},
          lastNudge: '2026-11-20',
        ),
        isTrue,
      );
    });

    test('counts calendar days across daylight-saving changes', () {
      // Europe's spring change is 29 March 2026, the US autumn one 1
      // November: either way the two days before are exactly the two
      // calendar days before.
      expect(
        due(
          now: DateTime(2026, 3, 30, 7),
          heard: {'2026-03-27'},
          firstLaunch: DateTime(2026, 3, 1),
        ),
        isTrue,
      );
      expect(
        due(
          now: DateTime(2026, 3, 30, 7),
          heard: {'2026-03-28'},
          firstLaunch: DateTime(2026, 3, 1),
        ),
        isFalse,
      );
      expect(
        due(
          now: DateTime(2026, 11, 2, 0, 30),
          heard: {'2026-10-30'},
          firstLaunch: DateTime(2026, 10, 1),
        ),
        isTrue,
      );
      expect(
        calendarDaysBetween(
          DateTime(2026, 3, 28, 23),
          DateTime(2026, 3, 30, 0, 30),
        ),
        2,
      );
      expect(
        calendarDaysBetween(
          DateTime(2026, 10, 31, 0, 30),
          DateTime(2026, 11, 1, 23, 30),
        ),
        1,
      );
    });
  });

  group('briefingWhenLabel', () {
    test('today, tomorrow, or a weekday', () {
      final now = DateTime(2026, 11, 26, 1, 0); // Thursday, 1 AM
      expect(
        briefingWhenLabel(DateTime(2026, 11, 26, 7), now),
        'today at 7:00 AM',
      );
      expect(
        briefingWhenLabel(DateTime(2026, 11, 27, 7), now),
        'tomorrow at 7:00 AM',
      );
      expect(
        briefingWhenLabel(DateTime(2026, 11, 28, 19, 30), now),
        'on Saturday at 7:30 PM',
      );
    });

    test('just before midnight, the morning is tomorrow', () {
      final now = DateTime(2026, 11, 26, 23, 50);
      expect(
        briefingWhenLabel(nextBriefingAt(now, ['07:00'])!, now),
        'tomorrow at 7:00 AM',
      );
    });

    test('nextBriefingAt picks the soonest time still ahead', () {
      final now = DateTime(2026, 11, 26, 8);
      expect(
        nextBriefingAt(now, ['07:00', '18:00']),
        DateTime(2026, 11, 26, 18),
      );
      expect(nextBriefingAt(now, ['07:00']), DateTime(2026, 11, 27, 7));
      expect(nextBriefingAt(now, ['bad']), isNull);
      // Across a DST change it stays on the clock time.
      expect(
        nextBriefingAt(DateTime(2026, 3, 28, 8), ['07:00']),
        DateTime(2026, 3, 29, 7),
      );
    });
  });

  group('day-one note', () {
    test('fires at 8 PM when that is ahead and before the first briefing', () {
      final now = DateTime(2026, 11, 26, 14);
      expect(
        dayOneNudgeAt(now: now, firstBriefing: DateTime(2026, 11, 27, 7)),
        DateTime(2026, 11, 26, 20),
      );
      // Too late today.
      expect(
        dayOneNudgeAt(
          now: DateTime(2026, 11, 26, 21),
          firstBriefing: DateTime(2026, 11, 27, 7),
        ),
        isNull,
      );
      // The first briefing comes first.
      expect(
        dayOneNudgeAt(now: now, firstBriefing: DateTime(2026, 11, 26, 18)),
        isNull,
      );
    });

    test('says what was heard, or nothing when nothing was', () {
      final first = DateTime(2026, 11, 27, 7);
      expect(
        dayOneNudgeBody(12, first),
        'Echo has heard 12 messages today. Your first briefing is ready at 7:00 AM.',
      );
      expect(
        dayOneNudgeBody(1, first),
        startsWith('Echo has heard 1 message today.'),
      );
      expect(dayOneNudgeBody(0, first), isNull);
    });
  });

  group('FirstBriefingPanel', () {
    Future<void> pump(
      WidgetTester tester, {
      required Map<String, Object> prefs,
      required Stream<void> changes,
      required int Function() count,
      double textScale = 1,
    }) async {
      SharedPreferences.setMockInitialValues(prefs);
      final settings = SettingsCubit();
      addTearDown(settings.close);
      await tester.pumpWidget(
        BlocProvider.value(
          value: settings,
          child: MaterialApp(
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: Scaffold(
                  body: FirstBriefingPanel(
                    clock: () => DateTime(2026, 11, 26, 14),
                    changes: changes,
                    countSince: (_) async => count(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'shows the first briefing and a live count before any briefing',
      (tester) async {
        final changes = StreamController<void>.broadcast();
        addTearDown(changes.close);
        var n = 3;
        await pump(
          tester,
          prefs: {
            'briefing_times': ['07:00'],
          },
          changes: changes.stream,
          count: () => n,
        );
        expect(find.text('Your first full briefing arrives'), findsOneWidget);
        expect(find.text('tomorrow at 7:00 AM'), findsOneWidget);
        expect(
          find.text('Echo has heard 3 messages so far today.'),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(
            'First briefing tomorrow at 7:00 AM. Change time',
          ),
          findsOneWidget,
        );

        n = 4;
        changes.add(null);
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(
          find.text('Echo has heard 4 messages so far today.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('says "today at" for a briefing later today', (tester) async {
      await pump(
        tester,
        prefs: {
          'briefing_times': ['21:00'],
        },
        changes: const Stream.empty(),
        count: () => 0,
      );
      expect(find.text('today at 9:00 PM'), findsOneWidget);
      expect(find.textContaining('Echo is listening'), findsOneWidget);
    });

    testWidgets('hidden once a briefing exists', (tester) async {
      await pump(
        tester,
        prefs: {
          'briefing_times': ['07:00'],
          'cached_briefing_date': '2026-11-26',
        },
        changes: const Stream.empty(),
        count: () => 5,
      );
      expect(find.byType(FirstBriefingCard), findsNothing);
    });

    testWidgets('hidden once a briefing has been heard', (tester) async {
      await pump(
        tester,
        prefs: {
          'briefing_times': ['07:00'],
          'briefings_heard_total': 2,
        },
        changes: const Stream.empty(),
        count: () => 5,
      );
      expect(find.byType(FirstBriefingCard), findsNothing);
    });

    testWidgets('fits at large text sizes', (tester) async {
      await pump(
        tester,
        prefs: {
          'briefing_times': ['07:00'],
        },
        changes: const Stream.empty(),
        count: () => 120,
        textScale: 2,
      );
      expect(find.byType(FirstBriefingCard), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
