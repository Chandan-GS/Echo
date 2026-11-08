import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_echo/core/services/streak_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('stepStreak', () {
    StreakStep step(String? last, int current, {Set<String> mended = const {}}) =>
        stepStreak(
          last: last,
          current: current,
          longest: 9,
          today: '2026-11-08',
          yesterday: '2026-11-07',
          mended: mended,
        );

    test('the next day adds one', () {
      expect(step('2026-11-07', 4).current, 5);
    });

    test('one missed day is mended, and adds only today', () {
      final s = step('2026-11-06', 4);
      expect(s.current, 5);
      expect(s.mended, '2026-11-07');
    });

    test('a second mend within the week starts over', () {
      final s = step('2026-11-06', 4, mended: {'2026-11-03'});
      expect(s.current, 1);
      expect(s.mended, isNull);
    });

    test('a mend a week ago does not block this one', () {
      expect(step('2026-11-06', 4, mended: {'2026-10-31'}).current, 5);
    });

    test('two missed days cannot be mended', () {
      final s = step('2026-11-05', 4);
      expect(s.current, 1);
      expect(s.mended, isNull);
    });

    test('nothing to mend without a streak', () {
      expect(step('2026-11-06', 0).mended, isNull);
    });

    test('a clock moved back keeps the streak and does not count', () {
      final s = step('2026-11-09', 4);
      expect(s.current, 4);
      expect(s.advanced, isFalse);
    });

    test('crossing a month and a year is one day', () {
      expect(streakDaysBetween('2026-12-31', '2027-01-01'), 1);
    });

    test('an unreadable date is not a crash', () {
      expect(streakDaysBetween('garbage', '2026-11-08'), isNull);
    });
  });

  group('StreakService', () {
    test('a streak from an older version carries on untouched', () async {
      SharedPreferences.setMockInitialValues({
        'streak_last_heard_date': _key(1),
        'streak_current': 12,
        'streak_longest': 20,
        'streak_heard_csv': _key(1),
      });
      final service = StreakService();
      expect((await service.current()).current, 12);
      final info = await service.recordEveningWrapCleared();
      expect(info.current, 13);
      expect(info.longest, 20);
    });

    test('the wrap and the briefing count the same day once', () async {
      SharedPreferences.setMockInitialValues({});
      final service = StreakService();
      expect((await service.recordEveningWrapCleared()).current, 1);
      expect((await service.recordHeard()).current, 1);
      expect(await service.briefingsHeard(), 1);
    });

    test('the day after a miss still reports the streak, as mendable', () async {
      SharedPreferences.setMockInitialValues({
        'streak_last_heard_date': _key(2),
        'streak_current': 6,
        'streak_longest': 6,
      });
      final info = await StreakService().current();
      expect(info.current, 6);
      expect(info.mendable, _key(1));
    });

    test('mending marks the missed day and joins it to the chain', () async {
      SharedPreferences.setMockInitialValues({
        'streak_last_heard_date': _key(2),
        'streak_current': 6,
        'streak_longest': 6,
      });
      final service = StreakService();
      expect((await service.recordHeard()).current, 7);
      expect(await service.mendedDates(), {_key(1)});
      expect(await service.heardDates(), containsAll([_key(0), _key(1)]));
      expect((await service.current()).mendable, isNull);
    });

    test('a snapshot from an older phone imports with nothing mended', () async {
      SharedPreferences.setMockInitialValues({});
      final service = StreakService();
      await service.importSnapshot({'current': 3, 'longest': 5});
      expect(await service.mendedDates(), isEmpty);
    });

    test('first ever recordHeard starts a streak of 1', () async {
      SharedPreferences.setMockInitialValues({});
      final info = await StreakService().recordHeard();
      expect(info.current, 1);
      expect(info.longest, 1);
    });

    test('recording again the same day is a no-op', () async {
      final today = _todayKey();
      SharedPreferences.setMockInitialValues({
        'streak_last_heard_date': today,
        'streak_current': 3,
        'streak_longest': 5,
      });
      final info = await StreakService().recordHeard();
      expect(info.current, 3);
      expect(info.longest, 5);
    });

    test('recording the day after yesterday increments the streak', () async {
      final yesterday = _dateKey(DateTime.now().subtract(const Duration(days: 1)));
      SharedPreferences.setMockInitialValues({
        'streak_last_heard_date': yesterday,
        'streak_current': 4,
        'streak_longest': 4,
      });
      final info = await StreakService().recordHeard();
      expect(info.current, 5);
      expect(info.longest, 5);
    });

    test('a gap of more than a day resets the streak to 1', () async {
      final longAgo = _dateKey(DateTime.now().subtract(const Duration(days: 5)));
      SharedPreferences.setMockInitialValues({
        'streak_last_heard_date': longAgo,
        'streak_current': 10,
        'streak_longest': 10,
      });
      final info = await StreakService().recordHeard();
      expect(info.current, 1);
      expect(info.longest, 10); // longest is preserved, not overwritten down.
    });

    test('current() reports 0 without mutating state once the streak lapses',
        () async {
      final longAgo = _dateKey(DateTime.now().subtract(const Duration(days: 5)));
      SharedPreferences.setMockInitialValues({
        'streak_last_heard_date': longAgo,
        'streak_current': 10,
        'streak_longest': 10,
      });
      final service = StreakService();
      final info = await service.current();
      expect(info.current, 0);
      expect(info.longest, 10);

      // Confirm nothing was persisted/mutated by the read-only check.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('streak_current'), 10);
      expect(prefs.getString('streak_last_heard_date'), longAgo);
    });

    test('current() still reports the live streak on the same or next day',
        () async {
      final today = _todayKey();
      SharedPreferences.setMockInitialValues({
        'streak_last_heard_date': today,
        'streak_current': 2,
        'streak_longest': 2,
      });
      final info = await StreakService().current();
      expect(info.current, 2);
    });
  });
}

String _todayKey() => _dateKey(DateTime.now());

String _key(int daysAgo) {
  final now = DateTime.now();
  return _dateKey(DateTime(now.year, now.month, now.day - daysAgo));
}

String _dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
