import 'package:flutter/foundation.dart';
import 'package:project_echo/features/echo/data/context/chat_context_store.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/relevance/temporal_relevance.dart';
import 'package:project_echo/features/echo/data/waiting/wait_intent.dart';
import 'package:project_echo/features/echo/data/waiting/waiting_store.dart';
import 'package:project_echo/features/echo/data/wrap/evening_wrap.dart';
import 'package:project_echo/features/todo/data/todo_item.dart';
import 'package:project_echo/features/todo/data/todo_store.dart';
import 'package:project_echo/features/vault/data/app_access.dart';

/// Gathers tonight's wrap from what's already on the phone. No model and no
/// network, so it works with nothing downloaded and from the alarm isolate.
class WrapStore {
  WrapStore._();

  static Future<EveningWrap> build(DateTime now) async {
    final today = startOfDay(now);
    final tomorrow = DateTime(today.year, today.month, today.day + 1);

    var waiting = const <WrapWaiting>[];
    try {
      final feed = await WaitingStore.load(now);
      waiting = [
        for (final w in feed.waiting)
          WrapWaiting(_waitingName(w.message), _daysSince(w.message, today)),
      ];
    } catch (e) {
      debugPrint('Evening wrap could not read waiting: $e');
    }

    final (items, _) = await TodoStore().load();
    final onToday = _on(items, today);
    final onTomorrow = _on(items, tomorrow);
    final open = onToday.where((i) => !i.done).map((i) => i.title).toList();

    final entries = await withoutExcludedSources(
      await IsarDataSource.getAllEntries(),
    );
    final turns = await ChatContextStore.loadMyTurns();

    final input = WrapInput(
      waiting: waiting,
      doneToday: onToday.where((i) => i.done).length,
      totalToday: onToday.length,
      openToday: open,
      tomorrowFirst: onTomorrow.firstOrNull?.title,
      tomorrowTime: onTomorrow.firstOrNull?.time,
      tomorrowCount: onTomorrow.length,
      owed: _owed(entries, turns, now),
      hasAnyData: entries.isNotEmpty || items.isNotEmpty,
    );
    return buildEveningWrap(input);
  }

  static List<TodoItem> _on(List<TodoItem> items, DateTime day) =>
      items.where((i) => i.day == day).toList()
        ..sort((a, b) => a.sort.compareTo(b.sort));

  static String _waitingName(RawData m) => m.sender.trim().isNotEmpty
      ? m.sender.trim()
      : (m.threadTitle?.trim().isNotEmpty ?? false)
      ? m.threadTitle!.trim()
      : m.source;

  static int _daysSince(RawData m, DateTime today) {
    final t = m.timestamp;
    return today.difference(DateTime(t.year, t.month, t.day)).inDays;
  }

  static List<WrapOwed> _owed(
    List<RawData> entries,
    MyTurns turns,
    DateTime now,
  ) {
    final threads = <String, ({String name, DateTime lastHeard, bool isGroup})>{};
    for (final e in entries) {
      final thread = e.thread;
      if (thread == null) continue;
      final seen = threads[thread];
      if (seen != null && !e.timestamp.isAfter(seen.lastHeard)) continue;
      final name = e.isGroup
          ? (e.threadTitle ?? e.sender)
          : (e.sender.isEmpty ? (e.threadTitle ?? e.source) : e.sender);
      threads[thread] = (
        name: name,
        lastHeard: e.timestamp,
        isGroup: e.isGroup,
      );
    }
    final latest = [
      for (final entry in turns.byThread.entries)
        if (entry.value.isNotEmpty)
          (
            thread: entry.key,
            at: entry.value.last.at,
            text: entry.value.last.text,
          ),
    ];
    return owedFromTurns(
      turns: latest,
      threads: threads,
      asksSomething: (text) =>
          classifyWait(text, isGroup: false).needsReply,
      now: now,
    );
  }
}
