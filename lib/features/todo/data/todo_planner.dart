import 'dart:convert';

import 'package:project_echo/features/echo/data/datasources/briefing_prompt.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/relevance/briefing_selection.dart';
import 'package:project_echo/features/echo/data/relevance/temporal_relevance.dart';
import 'package:project_echo/features/todo/data/todo_item.dart';

/// The pure parts of making and updating the to-do list: prompt text, reply
/// parsing, and applying the result. The model only ever returns a short
/// title plus which numbered notification it came from; the day, time and
/// source are worked out here from that notification, so the reply stays a
/// few dozen tokens and times can't be misread.

const makeInstruction =
    'You turn a person\'s notifications into a short to-do list. Each numbered '
    'line is one notification, starting with a label in square brackets saying '
    'when it applies. Reply with JSON only: an array of objects {"t": string, '
    '"s": number}. "t" is the to-do in plain words, at most 8 words, starting '
    'with a verb where it reads naturally, for example "Prep the deck for the '
    'client demo". "s" is the number of the notification it comes from. '
    'Include only things the person needs to do, attend or remember. Skip '
    'promotions, OTPs, delivery updates, receipts and general news. One item '
    'per real task: merge notifications about the same thing. Never invent '
    'anything.';

const updateInstruction =
    'You keep a person\'s to-do list up to date. "Open items" are already on '
    'the list, as id: text · when. "New notifications" are numbered, each '
    'starting with a label in square brackets saying when it applies. Reply '
    'with JSON only: {"add": [{"t": string, "s": number}], "change": [{"id": '
    'number, "s": number}]}. Use "change" when a new notification is about an '
    'open item (for example its time moved), naming the item\'s id and the '
    'notification number. Use "add" only for genuinely new things, with "t" '
    'at most 8 words starting with a verb where it reads naturally. Skip '
    'promotions, OTPs, delivery updates, receipts and general news. Never '
    'remove anything and never invent anything. Reply {"add": [], "change": '
    '[]} if nothing applies.';

const _maxSourceChars = 200;

/// "1. [Today (Sat 26 Sep), 6:30 PM] Neha (Slack): Client demo is today…"
String numberedLines(List<BriefingItem> items, DateTime now) {
  final lines = <String>[];
  for (var i = 0; i < items.length; i++) {
    final e = items[i].entry;
    lines.add(
      '${i + 1}. ${formatNotification(source: e.source, sender: e.sender, content: _clip(rewriteRelativeDays(e.content, e.timestamp, now), _maxSourceChars), when: describeEntry(e, items[i].window, now))}',
    );
  }
  return lines.join('\n');
}

/// "3: Prep the deck for the client demo · today 6:30 PM"
String openItemLines(List<TodoItem> items, DateTime now) => items
    .map(
      (i) =>
          '${i.id}: ${i.title} · ${_dayWord(i.day, now)}'
          '${i.time == null ? '' : ' ${i.time}'}',
    )
    .join('\n');

typedef NewTodo = ({String title, int source});
typedef TodoChange = ({int id, int source});

List<NewTodo> parseMakeReply(String raw) {
  final decoded = _decodeJson(raw);
  final list = decoded is List
      ? decoded
      : decoded is Map
      ? (decoded['add'] ?? decoded['items'] ?? const [])
      : const [];
  return _newTodos(list);
}

({List<NewTodo> add, List<TodoChange> change}) parseUpdateReply(String raw) {
  final decoded = _decodeJson(raw);
  if (decoded is List) return (add: _newTodos(decoded), change: const []);
  if (decoded is! Map) return (add: const [], change: const []);
  final changes = <TodoChange>[];
  for (final c in (decoded['change'] as List?) ?? const []) {
    if (c is Map && c['id'] is num && c['s'] is num) {
      changes.add((
        id: (c['id'] as num).toInt(),
        source: (c['s'] as num).toInt(),
      ));
    }
  }
  return (
    add: _newTodos((decoded['add'] as List?) ?? const []),
    change: changes,
  );
}

List<NewTodo> _newTodos(List list) {
  final out = <NewTodo>[];
  for (final t in list) {
    if (t is Map && t['t'] is String && t['s'] is num) {
      final title = (t['t'] as String).trim();
      if (title.isNotEmpty) {
        out.add((title: _clip(title, 80), source: (t['s'] as num).toInt()));
      }
    }
  }
  return out;
}

Object? _decodeJson(String raw) {
  var text = raw.trim();
  // Tolerate ```json fences and prose around the JSON.
  final start = text.indexOf(RegExp(r'[\[{]'));
  if (start < 0) return null;
  final end = text.lastIndexOf(RegExp(r'[\]}]'));
  if (end <= start) return null;
  text = text.substring(start, end + 1);
  try {
    return jsonDecode(text);
  } catch (_) {
    return null;
  }
}

/// A to-do built from [candidate], with [title] from the model (or
/// [localTitle] when there is no model).
TodoItem itemFrom(BriefingItem candidate, String title, int id, DateTime now) {
  final e = candidate.entry;
  final w = candidate.window;
  final today = startOfDay(now);
  var day = w.explicit ? startOfDay(w.start) : today;
  if (day.isBefore(today)) day = today; // a multi-day span that began earlier
  return TodoItem(
    id: id,
    title: title,
    day: day,
    time: w.explicit && w.hasTime ? compactTime(w) : null,
    sort: w.explicit && w.hasTime
        ? w.start.hour * 60 + w.start.minute
        : TodoItem.noTimeSort,
    sender: e.sender,
    app: displaySource(e.source, const {}),
    sourceText: _clip(rewriteRelativeDays(e.content, e.timestamp, now), 240),
    sourceKey: sourceKeyOf(e),
    created: now,
  );
}

String sourceKeyOf(RawData e) =>
    '${e.sender}|${e.timestamp.millisecondsSinceEpoch}';

/// Without a model: the notification's own first sentence, trimmed.
String localTitle(RawData e, DateTime now) {
  final text = rewriteRelativeDays(e.content, e.timestamp, now).trim();
  if (text.isEmpty) return _clip(e.sender, 60);
  final first = text.split(RegExp(r'(?<=[.!?])\s|\n')).first.trim();
  final sentence = first.replaceAll(RegExp(r'[.!]+$'), '');
  return _clip(sentence, 70);
}

/// A new list from [picked] ("make"): one item per model to-do, skipping
/// notifications already on the list. Nothing existing is touched.
List<TodoItem> applyMake({
  required List<TodoItem> existing,
  required List<BriefingItem> candidates,
  required List<NewTodo> todos,
  required int firstId,
  required DateTime now,
}) {
  final keys = existing.map((i) => i.sourceKey).toSet();
  final added = <TodoItem>[];
  var id = firstId;
  for (final t in todos) {
    if (t.source < 1 || t.source > candidates.length) continue;
    final c = candidates[t.source - 1];
    final key = sourceKeyOf(c.entry);
    if (keys.contains(key)) continue;
    keys.add(key);
    added.add(itemFrom(c, t.title, id++, now));
  }
  return [...existing, ...added];
}

/// An update: additions are marked new, changes are applied in place with the
/// old time kept as [TodoItem.movedFrom]. Items are never removed, and done
/// items stay done.
List<TodoItem> applyUpdate({
  required List<TodoItem> existing,
  required List<BriefingItem> candidates,
  required List<NewTodo> add,
  required List<TodoChange> change,
  required int firstId,
  required DateTime now,
}) {
  final byId = {for (final i in existing) i.id: i.copyWith(isNew: false)};
  final keys = existing.map((i) => i.sourceKey).toSet();

  for (final c in change) {
    final item = byId[c.id];
    if (item == null || c.source < 1 || c.source > candidates.length) continue;
    final cand = candidates[c.source - 1];
    final fresh = itemFrom(cand, item.title, item.id, now);
    final moved = fresh.time != item.time || fresh.day != item.day;
    byId[c.id] = item.copyWith(
      day: fresh.day,
      time: fresh.time,
      sort: fresh.sort,
      sourceText: fresh.sourceText,
      sourceKey: fresh.sourceKey,
      movedFrom: moved
          ? (item.time ?? _dayWord(item.day, now))
          : item.movedFrom,
    );
    keys.add(fresh.sourceKey);
  }

  final ordered = [for (final i in existing) byId[i.id]!];
  var id = firstId;
  for (final t in add) {
    if (t.source < 1 || t.source > candidates.length) continue;
    final c = candidates[t.source - 1];
    final key = sourceKeyOf(c.entry);
    if (keys.contains(key)) continue;
    keys.add(key);
    ordered.add(itemFrom(c, t.title, id++, now).copyWith(isNew: true));
  }
  return ordered;
}

/// "6:30 PM", "5 PM", "4–6 PM", "11 AM–1 PM".
String compactTime(RelevanceWindow w) {
  String clock(DateTime t, {bool meridiem = true}) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute == 0 ? '' : ':${t.minute.toString().padLeft(2, '0')}';
    return meridiem ? '$h$m ${t.hour < 12 ? 'AM' : 'PM'}' : '$h$m';
  }

  if (!w.hasEndTime) return clock(w.start);
  final sameHalf =
      (w.start.hour < 12) == (w.end.hour < 12) &&
      startOfDay(w.start) == startOfDay(w.end);
  return sameHalf
      ? '${clock(w.start, meridiem: false)}–${clock(w.end)}'
      : '${clock(w.start)}–${clock(w.end)}';
}

String _dayWord(DateTime day, DateTime now) {
  final diff = (startOfDay(day).difference(startOfDay(now)).inHours / 24)
      .round();
  return switch (diff) {
    0 => 'today',
    1 => 'tomorrow',
    -1 => 'yesterday',
    _ => shortDate(day),
  };
}

String _clip(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max).trimRight()}…';
