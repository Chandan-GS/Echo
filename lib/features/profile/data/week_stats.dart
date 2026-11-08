import 'dart:convert';

import 'package:isar/isar.dart';
import 'package:project_echo/features/echo/data/context/chat_context_store.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/todo/data/todo_item.dart';
import 'package:project_echo/features/todo/data/todo_store.dart';
import 'package:project_echo/features/vault/data/app_access.dart';
import 'package:project_echo/features/vault/data/daily_stats.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A reply Echo saw: which conversation, and when.
typedef SeenAnswer = ({String thread, DateTime at});

/// The owner's last seven days with Echo: who they got back to, to-dos ticked
/// off, replies sent through Echo, messages read for them, and what quiet
/// hours held. Numbers only, worked out on the phone.
class WeekStats {
  final int todosDone;
  final int replies;

  /// Messages read each day, oldest first, today last.
  final List<int> readByDay;

  /// The first day of [readByDay].
  final DateTime from;

  /// To-dos that were due this week, done or not.
  final int todosDue;

  /// People got back to within a day of their message. Only replies Echo saw:
  /// one typed inside a chat app is invisible, so this is never "ignored".
  final int peopleAnswered;

  /// [peopleAnswered] by day, oldest first, today last.
  final List<int> answeredByDay;

  /// Notifications quiet hours held back.
  final int held;

  const WeekStats({
    required this.todosDone,
    required this.replies,
    required this.readByDay,
    required this.from,
    this.todosDue = 0,
    this.peopleAnswered = 0,
    this.answeredByDay = const [0, 0, 0, 0, 0, 0, 0],
    this.held = 0,
  });

  /// Nothing to show yet, on a phone that's new to Echo.
  bool get isEmpty =>
      peopleAnswered == 0 && todosDue == 0 && read == 0 && held == 0;

  int get read => readByDay.fold(0, (a, n) => a + n);

  static const _repliesKey = 'echo_replies_sent_v1';

  static Future<WeekStats> load(DateTime now) async {
    final (items, _) = await TodoStore().load();
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final week = await DailyStats.week(now);
    final from = DateTime(now.year, now.month, now.day - 6);
    return summarise(
      items: items,
      replies: _decode(prefs.getString(_repliesKey)),
      readByDay: [for (final d in week) d.total],
      answers: await _answers(from, now),
      held: await _heldSince(from),
      now: now,
    );
  }

  /// What quiet hours held back since [from] and is still kept.
  static Future<int> _heldSince(DateTime from) async {
    final isar = await IsarDataSource.instance;
    return isar.rawDatas.filter().heldAtGreaterThan(from).count();
  }

  /// Each turn the owner took this week within a day of the message before
  /// it, skipping apps they've switched off.
  static Future<List<SeenAnswer>> _answers(DateTime from, DateTime now) async {
    final turns = (await ChatContextStore.loadMyTurns()).byThread;
    final isar = await IsarDataSource.instance;
    final byMessage = <RawData, SeenAnswer>{};
    for (final MapEntry(key: thread, value: list) in turns.entries) {
      for (final turn in list) {
        if (turn.at.isBefore(from) || turn.at.isAfter(now)) continue;
        final asked = await isar.rawDatas
            .filter()
            .threadEqualTo(thread)
            .timestampLessThan(turn.at, include: true)
            .sortByTimestampDesc()
            .findFirst();
        if (asked != null &&
            turn.at.difference(asked.timestamp) <= const Duration(days: 1)) {
          byMessage[asked] = (thread: thread, at: turn.at);
        }
      }
    }
    final allowed = await withoutExcludedSources(byMessage.keys.toList());
    return [for (final m in allowed) byMessage[m]!];
  }

  /// The pure part of [load]. [replies] are when replies were sent.
  static WeekStats summarise({
    required List<TodoItem> items,
    required List<DateTime> replies,
    required List<int> readByDay,
    required DateTime now,
    List<SeenAnswer> answers = const [],
    int held = 0,
  }) {
    final from = DateTime(now.year, now.month, now.day - 6);
    bool inWeek(DateTime t) => !t.isBefore(from) && !t.isAfter(now);
    bool doneThisWeek(TodoItem i) =>
        i.done && i.doneAt != null && inWeek(i.doneAt!);
    final week = answers.where((a) => inWeek(a.at)).toList();
    final perDay = List.generate(7, (_) => <String>{});
    for (final a in week) {
      final day = DateTime.utc(
        a.at.year,
        a.at.month,
        a.at.day,
      ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
      if (day >= 0 && day < 7) perDay[day].add(a.thread);
    }
    return WeekStats(
      todosDone: items.where(doneThisWeek).length,
      todosDue: items.where((i) => inWeek(i.day) || doneThisWeek(i)).length,
      replies: replies.where(inWeek).length,
      readByDay: readByDay,
      from: from,
      peopleAnswered: week.map((a) => a.thread).toSet().length,
      answeredByDay: [for (final d in perDay) d.length],
      held: held,
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
