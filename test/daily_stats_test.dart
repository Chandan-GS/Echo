import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/features/vault/data/daily_stats.dart';

void main() {
  final now = DateTime(2026, 9, 26, 18, 48);

  test('counts a signal into its day, hour and app', () {
    var store = <String, dynamic>{};
    store = DailyStats.added(
      store,
      'Whatsapp',
      DateTime(2026, 9, 26, 9, 5),
      now,
    );
    store = DailyStats.added(
      store,
      'Whatsapp',
      DateTime(2026, 9, 26, 9, 40),
      now,
    );
    store = DailyStats.added(store, 'Slack', DateTime(2026, 9, 26, 14), now);
    final today = DailyStats.weekFrom(store, now).last;
    expect(today.total, 3);
    expect(today.hours[9], 2);
    expect(today.hours[14], 1);
    expect(today.top(1).single.key, 'Whatsapp');
  });

  test('keeps seven days, oldest first, and drops older ones', () {
    var store = <String, dynamic>{};
    store = DailyStats.added(store, 'Gmail', DateTime(2026, 9, 18, 10), now);
    store = DailyStats.added(store, 'Gmail', DateTime(2026, 9, 20, 10), now);
    expect(store.keys, ['2026-09-20']);
    final week = DailyStats.weekFrom(store, now);
    expect(week, hasLength(7));
    expect(week.first.day, DateTime(2026, 9, 20));
    expect(week.first.total, 1);
    expect(week.last.day, DateTime(2026, 9, 26));
  });

  test(
    'merging live counts with what is still in the Vault takes the larger',
    () {
      final a = DayStats(
        DateTime(2026, 9, 26),
        [for (var h = 0; h < 24; h++) h == 9 ? 5 : 0],
        {'Whatsapp': 5},
      );
      final b = DayStats(
        DateTime(2026, 9, 26),
        [for (var h = 0; h < 24; h++) h == 9 ? 3 : (h == 8 ? 2 : 0)],
        {'Whatsapp': 3, 'Slack': 2},
      );
      final m = a.mergeMax(b);
      expect(m.hours[9], 5);
      expect(m.hours[8], 2);
      expect(m.apps, {'Whatsapp': 5, 'Slack': 2});
    },
  );
}
