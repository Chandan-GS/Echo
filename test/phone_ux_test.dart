import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/core/services/pending_autoplay.dart';
import 'package:project_echo/features/echo/presentation/screens/ask_ai_screen.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/for_you_view.dart';
import 'package:project_echo/features/vault/data/daily_stats.dart';
import 'package:project_echo/features/vault/presentation/cubit/vault_cubit.dart';
import 'package:project_echo/features/vault/presentation/widgets/vault_day_heading.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The daylight-saving cases matter where the clocks change; run them with
// e.g. TZ=America/New_York flutter test test/phone_ux_test.dart. They pass
// in any time zone.
void main() {
  group('PendingAutoplay', () {
    final now = DateTime(2026, 11, 26, 7, 30);

    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('a fresh mark is taken once', () async {
      final prefs = await SharedPreferences.getInstance();
      await PendingAutoplay.mark(prefs, now: now);
      expect(PendingAutoplay.isPending(prefs, now: now), isTrue);
      expect(await PendingAutoplay.take(prefs, now: now), isTrue);
      expect(await PendingAutoplay.take(prefs, now: now), isFalse);
    });

    test('a mark left behind does not play later', () async {
      final prefs = await SharedPreferences.getInstance();
      await PendingAutoplay.mark(prefs, now: now);
      final later = now.add(const Duration(days: 2));
      expect(PendingAutoplay.isPending(prefs, now: later), isFalse);
      expect(await PendingAutoplay.take(prefs, now: later), isFalse);
      expect(prefs.containsKey(PendingAutoplay.key), isFalse);
    });

    test('just inside and outside the window', () {
      expect(
        PendingAutoplay.isFresh(now.subtract(PendingAutoplay.window), now),
        isTrue,
      );
      expect(
        PendingAutoplay.isFresh(
          now.subtract(PendingAutoplay.window + const Duration(seconds: 1)),
          now,
        ),
        isFalse,
      );
      expect(
        PendingAutoplay.isFresh(now.add(const Duration(hours: 3)), now),
        isFalse,
      );
      expect(PendingAutoplay.isFresh(null, now), isFalse);
    });

    test('the undated mark of older versions is ignored and cleared', () async {
      SharedPreferences.setMockInitialValues({PendingAutoplay.legacyKey: true});
      final prefs = await SharedPreferences.getInstance();
      expect(PendingAutoplay.isPending(prefs, now: now), isFalse);
      expect(await PendingAutoplay.take(prefs, now: now), isFalse);
      expect(prefs.containsKey(PendingAutoplay.legacyKey), isFalse);
    });

    test('reads the Long MainActivity writes for the widget', () async {
      SharedPreferences.setMockInitialValues({
        PendingAutoplay.key: now.millisecondsSinceEpoch,
      });
      final prefs = await SharedPreferences.getInstance();
      expect(await PendingAutoplay.take(prefs, now: now), isTrue);
    });
  });

  group('Ask Echo follows the answer only near the bottom', () {
    test('at the bottom, and a little above it', () {
      expect(isNearBottom(1000, 1000), isTrue);
      expect(isNearBottom(950, 1000), isTrue);
    });
    test('scrolled up to reread', () {
      expect(isNearBottom(400, 1000), isFalse);
    });
  });

  group('RemindPill', () {
    final now = DateTime(2026, 11, 26, 19, 0);
    test('a time still ahead is kept', () {
      final at = now.add(const Duration(minutes: 40));
      expect(remindPillTime(at, now), at);
    });
    test('a time gone by (the pill sat on screen) is refused', () {
      expect(
        remindPillTime(now.subtract(const Duration(minutes: 5)), now),
        isNull,
      );
      expect(remindPillTime(now.add(const Duration(seconds: 30)), now), isNull);
    });
  });

  group('Vault blocks', () {
    test('blocking keeps every other block', () {
      expect(withBlock(['Slack'], 'Gmail', block: true), ['Slack', 'Gmail']);
    });
    test('unblocking a category already lifted elsewhere stays lifted', () {
      expect(withBlock(['Slack'], 'WhatsApp', block: false), ['Slack']);
    });
    test('blocking twice lists it once', () {
      expect(withBlock(['Gmail'], 'Gmail', block: true), ['Gmail']);
    });
  });

  group('Days across daylight saving', () {
    test('daysBefore steps calendar days', () {
      // US clocks went forward on 8 Mar 2026 and back on 1 Nov 2026.
      expect(
        DailyStats.daysBefore(DateTime(2026, 3, 9, 0, 30), 1),
        DateTime(2026, 3, 8),
      );
      expect(
        DailyStats.daysBefore(DateTime(2026, 11, 2, 23, 30), 1),
        DateTime(2026, 11, 1),
      );
      expect(
        DailyStats.daysBefore(DateTime(2026, 3, 1), 1),
        DateTime(2026, 2, 28),
      );
    });

    test('the week has seven different days across a change', () {
      final week = DailyStats.weekFrom({}, DateTime(2026, 3, 10, 0, 15));
      expect(
        [for (final d in week) DailyStats.dateKey(d.day)],
        [
          '2026-03-04',
          '2026-03-05',
          '2026-03-06',
          '2026-03-07',
          '2026-03-08',
          '2026-03-09',
          '2026-03-10',
        ],
      );
    });

    test('pruning keeps the seven days across a change', () {
      final store = {
        for (var d = 1; d <= 9; d++)
          '2026-11-${d.toString().padLeft(2, '0')}': {
            'h': List.filled(24, 0),
            'a': <String, int>{},
          },
      };
      final kept = DailyStats.pruned(store, DateTime(2026, 11, 8, 0, 30));
      expect(kept.keys.toList()..sort(), [
        '2026-11-02',
        '2026-11-03',
        '2026-11-04',
        '2026-11-05',
        '2026-11-06',
        '2026-11-07',
        '2026-11-08',
      ]);
    });

    test('Vault headings count calendar days', () {
      final now = DateTime(2026, 3, 9, 0, 30);
      expect(calendarDaysAgo(DateTime(2026, 3, 9), now), 0);
      expect(calendarDaysAgo(DateTime(2026, 3, 8), now), 1);
      expect(calendarDaysAgo(DateTime(2026, 3, 7), now), 2);
      expect(
        calendarDaysAgo(DateTime(2026, 11, 1), DateTime(2026, 11, 2, 23)),
        1,
      );
    });
  });
}
