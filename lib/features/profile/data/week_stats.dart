import 'dart:convert';

import 'package:project_echo/features/todo/data/todo_item.dart';
import 'package:project_echo/features/todo/data/todo_store.dart';
import 'package:project_echo/features/vault/data/daily_stats.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The owner's last seven days with Echo, for Profile: to-dos ticked off,
/// replies sent through Echo, and messages Echo read for them each day.
class WeekStats {
  final int todosDone;
  final int replies;

  /// Messages read each day, oldest first, today last.
  final List<int> readByDay;

  /// The first day of [readByDay].
  final DateTime from;

  const WeekStats({
    required this.todosDone,
    required this.replies,
    required this.readByDay,
    required this.from,
  });

  int get read => readByDay.fold(0, (a, n) => a + n);

  static const _repliesKey = 'echo_replies_sent_v1';

  static Future<WeekStats> load(DateTime now) async {
    final (items, _) = await TodoStore().load();
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final week = await DailyStats.week(now);
    return summarise(
      items: items,
      replies: _decode(prefs.getString(_repliesKey)),
      readByDay: [for (final d in week) d.total],
      now: now,
    );
  }

  /// The pure part of [load]. [replies] are when replies were sent.
  static WeekStats summarise({
    required List<TodoItem> items,
    required List<DateTime> replies,
    required List<int> readByDay,
    required DateTime now,
  }) {
    final from = DateTime(now.year, now.month, now.day - 6);
    bool inWeek(DateTime t) => !t.isBefore(from) && !t.isAfter(now);
    return WeekStats(
      todosDone: items
          .where((i) => i.done && i.doneAt != null && inWeek(i.doneAt!))
          .length,
      replies: replies.where(inWeek).length,
      readByDay: readByDay,
      from: from,
    );
  }

  /// A reply went out through Echo (sent, or written into the chat).
  static Future<void> countReply(DateTime at) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final week = at.subtract(const Duration(days: 7));
    final kept = [
      ..._decode(prefs.getString(_repliesKey)).where((t) => t.isAfter(week)),
      at,
    ];
    await prefs.setString(
      _repliesKey,
      jsonEncode([for (final t in kept) t.millisecondsSinceEpoch]),
    );
  }

  static List<DateTime> _decode(String? raw) {
    try {
      return [
        for (final ms in jsonDecode(raw ?? '[]') as List)
          DateTime.fromMillisecondsSinceEpoch(ms as int),
      ];
    } catch (_) {
      return const [];
    }
  }
}
