import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_echo/core/services/streak_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StreakService', () {
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

String _dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
