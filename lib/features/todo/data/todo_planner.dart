import 'dart:convert';

import 'package:project_echo/features/echo/data/context/chat_context_store.dart';
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

/// Notification lines say who a chat message was for (see formatEntry).
const _groupRule =
    'Group chat marked "not addressed to you" becomes a to-do only when it '
    'asks something of everyone in the group.';

/// A message that lists several tasks with their own times ("send the deck
/// by 4, call the vendor at 11 tomorrow, …") becomes one item per task. The
/// model copies each task's time words; the day and time are still worked
/// out here.
const _splitRule =
    'A notification that lists more than $splitAbove separate tasks becomes one '
    'item per task, all with that notification\'s "s", each with "w": the words '
    'from the notification saying when that task is due, copied exactly (for '
    'example "by 4 PM" or "tomorrow at 11"), left out when that task names no '
    'time. Any other notification gives at most one item.';

const makeInstruction =
    'You turn a person\'s notifications into a short to-do list. Each numbered '
    'line is one notification, starting with a label in square brackets saying '
    'when it applies. Reply with JSON only: an array of objects {"t": string, '
    '"s": number, "w"?: string}. "t" is the to-do in plain words, at most 8 '
    'words, starting with a verb where it reads naturally, for example "Prep '
    'the deck for the client demo". "s" is the number of the notification it '
    'comes from. Include only things the person needs to do, attend or '
    'remember. Skip promotions, OTPs, delivery updates, receipts and general '
    'news. Merge notifications about the same thing. $_splitRule $_groupRule '
    'Items from at most $maxListItems notifications, the most important first. '
    'Never invent anything.';

const updateInstruction =
    'You keep a person\'s to-do list up to date. "Open items" are already on '
    'the list, as id: text · when. "New notifications" are numbered, each '
    'starting with a label in square brackets saying when it applies. Reply '
    'with JSON only: {"add": [{"t": string, "s": number, "w"?: string}], '
    '"change": [{"id": number, "s": number}]}. Use "change" when a new '
    'notification is about an open item (for example its time moved), naming '
    'the item\'s id and the notification number. Use "add" only for genuinely '
    'new things, with "t" at most 8 words starting with a verb where it reads '
    'naturally. $_splitRule $_groupRule Skip promotions, OTPs, delivery '
    'updates, receipts and general news. Never remove anything and never '
    'invent anything. Reply {"add": [], "change": []} if nothing applies.';

/// Only a message with more tasks than this is split into one item per task.
const splitAbove = 3;

/// The most items one message can become.
const _maxPerMessage = 8;

const _maxSourceChars = 200;

/// A message that reads like a list keeps more of its text, so every task in
/// it reaches the model.
const _maxListSourceChars = 700;

/// A list is a short plan, not a copy of the inbox.
const maxListItems = 8;

/// Without a model: at most [maxListItems] notifications become to-dos,
/// preferring ones that name a date or time (the rest of the selection is
/// already ordered by importance).
List<int> localPicks(List<BriefingItem> candidates) {
  final order = [
    for (var i = 0; i < candidates.length; i++)
      if (candidates[i].window.explicit) i,
    for (var i = 0; i < candidates.length; i++)
      if (!candidates[i].window.explicit) i,
  ];
  return order.take(maxListItems).toList();
}

/// "1. [Today (Sat 26 Sep), 6:30 PM] Neha (Slack): Client demo is today…"
String numberedLines(
  List<BriefingItem> items,
  DateTime now, {
  MyTurns? myTurns,
}) {
  final lines = <String>[];
  for (var i = 0; i < items.length; i++) {
    final e = items[i].entry;
    final line = formatEntry(
      e,
      content: _clip(
        rewriteRelativeDays(e.content, e.timestamp, now),
        looksLikeList(e.content) ? _maxListSourceChars : _maxSourceChars,
      ),
      when: describeEntry(e, items[i].window, now),
      myTurns: myTurns,
    );
    lines.add('${i + 1}. $line');
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

/// A to-do from the model: its title, the notification it came from, and for
/// one task of a split message, the words saying when that task is due.
typedef NewTodo = ({String title, int source, String? when});
typedef TodoChange = ({int id, int source});

List<NewTodo> parseMakeReply(String raw) {
  final decoded = _decodeJson(raw);
  final list = decoded is List
      ? decoded
      : decoded is Map
      ? (decoded['add'] ?? decoded['items'] ?? const [])
      : const [];
  // The cap counts messages, so a split message doesn't crowd others out.
  final sources = <int>{};
  final out = <NewTodo>[];
  for (final t in _newTodos(list)) {
    if (!sources.contains(t.source)) {
      if (sources.length == maxListItems) continue;
      sources.add(t.source);
    }
    out.add(t);
  }
  return out;
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
      final when = t['w'] is String ? (t['w'] as String).trim() : '';
      if (title.isNotEmpty) {
        out.add((
          title: _clip(title, 80),
          source: (t['s'] as num).toInt(),
          when: when.isEmpty ? null : when,
        ));
      }
    }
  }
  return out;
}

/// A message becomes several items only when it has more than [splitAbove]
/// tasks; with two or three, its first item stands for it.
List<NewTodo> keepSplitsOnlyForLists(List<NewTodo> todos) {
  final perSource = <int, int>{};
  for (final t in todos) {
    perSource[t.source] = (perSource[t.source] ?? 0) + 1;
  }
  final taken = <int, int>{};
  final out = <NewTodo>[];
  for (final t in todos) {
    final count = perSource[t.source]!;
    final n = taken[t.source] = (taken[t.source] ?? 0) + 1;
    final split = count > splitAbove;
    if (n > (split ? _maxPerMessage : 1)) continue;
    out.add(split ? t : (title: t.title, source: t.source, when: null));
  }
  return out;
}

/// Whether [text] reads like a list of things: four or more lines, bullets or
/// numbered points.
bool looksLikeList(String text) {
  final points = RegExp(r'(^|\n)\s*([-•*]|\d{1,2}[.)])\s', multiLine: true);
  final lines = text.split('\n').where((l) => l.trim().isNotEmpty).length;
  return lines >= 4 || points.allMatches(text).length >= 4;
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
///
/// One task of a split message ([part]) takes its time from [when], its own
/// time words, not from the message as a whole; the message's day still
/// applies when [when] names only a time.
TodoItem itemFrom(
  BriefingItem candidate,
  String title,
  int id,
  DateTime now, {
  bool part = false,
  String? when,
}) {
  final e = candidate.entry;
  final today = startOfDay(now);
  var w = candidate.window;
  var timed = w.explicit && w.hasTime;
  if (part) {
    final own = when == null ? null : partWindow(when, e.timestamp, w);
    timed = own != null && own.hasTime;
    if (own != null) w = own;
  }
  var day = w.explicit ? startOfDay(w.start) : today;
  if (day.isBefore(today)) day = today; // a multi-day span that began earlier
  return TodoItem(
    id: id,
    title: title,
    day: day,
    time: timed ? compactTime(w) : null,
    sort: timed ? w.start.hour * 60 + w.start.minute : TodoItem.noTimeSort,
    sender: e.who,
    app: displaySource(e.source, const {}),
    sourceText: _clip(rewriteRelativeDays(e.content, e.timestamp, now), 240),
    sourceKey: sourceKeyOf(e),
    created: now,
  );
}

String sourceKeyOf(RawData e) =>
    '${e.sender}|${e.timestamp.millisecondsSinceEpoch}';

/// The key of the [n]th task (from 1) of a split message: the first keeps the
/// message's own key, so a message already on the list is never added again.
String partKey(String key, int n) => n == 1 ? key : '$key#$n';

final _dayWords = RegExp(
  r'\b(today|tonight|tomorrow|tmrw|tmr|yesterday|mon|tue|wed|thu|fri|sat|sun|'
  r'jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\b|'
  r'\b\d{1,2}(st|nd|rd|th)\b|\b\d{1,2}/\d{1,2}\b',
  caseSensitive: false,
);

/// When one task of a split message applies: the time named in [when]. If
/// [when] gives only a time ("by 4 PM"), it's on the day the whole message
/// is about ([message]), not necessarily the day it arrived.
RelevanceWindow? partWindow(
  String when,
  DateTime receivedAt,
  RelevanceWindow message,
) {
  final found = extractExplicitWindows(when, receivedAt);
  if (found.isEmpty) return null;
  final own = found.first;
  if (_dayWords.hasMatch(when) || !message.explicit) return own;
  final day = message.start;
  final first = startOfDay(own.start);
  DateTime onDay(DateTime t) => DateTime(
    day.year,
    day.month,
    day.day + startOfDay(t).difference(first).inDays,
    t.hour,
    t.minute,
  );
  return RelevanceWindow(
    start: onDay(own.start),
    end: onDay(own.end),
    explicit: true,
    hasTime: own.hasTime,
    hasEndTime: own.hasEndTime,
  );
}

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
  return [...existing, ..._newItems(todos, candidates, keys, firstId, now)];
}

/// Items for [todos] whose notification isn't in [keys] yet, numbered from
/// [firstId]. A split message gives several items, each keyed by [partKey].
List<TodoItem> _newItems(
  List<NewTodo> todos,
  List<BriefingItem> candidates,
  Set<String> keys,
  int firstId,
  DateTime now,
) {
  final bySource = <int, List<NewTodo>>{};
  for (final t in keepSplitsOnlyForLists(todos)) {
    if (t.source < 1 || t.source > candidates.length) continue;
    bySource.putIfAbsent(t.source, () => []).add(t);
  }
  final added = <TodoItem>[];
  var id = firstId;
  for (final MapEntry(key: source, value: parts) in bySource.entries) {
    final c = candidates[source - 1];
    final key = sourceKeyOf(c.entry);
    if (keys.contains(key)) continue;
    keys.add(key);
    final split = parts.length > 1;
    for (var n = 1; n <= parts.length; n++) {
      final t = parts[n - 1];
      final item = itemFrom(c, t.title, id++, now, part: split, when: t.when);
      added.add(split ? item.copyWith(sourceKey: partKey(key, n)) : item);
    }
  }
  return added;
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

  return [
    for (final i in existing) byId[i.id]!,
    for (final item in _newItems(add, candidates, keys, firstId, now))
      item.copyWith(isNew: true),
  ];
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
