import 'package:project_echo/features/echo/data/context/chat_context_store.dart';
import 'package:project_echo/features/echo/data/waiting/waiting_store.dart';
import 'package:project_echo/features/people/data/group_rules.dart';
import 'package:project_echo/features/people/data/person_tally.dart';
import 'package:project_echo/features/todo/data/owed_store.dart';
import 'package:project_echo/features/todo/data/todo_item.dart';
import 'package:project_echo/features/todo/data/todo_planner.dart';

/// How long a question hangs before Echo offers to follow it up.
const followUpAfter = Duration(days: 2);

/// One thing the owner still has to do for someone.
class OweLine {
  final String title;
  final String meta;
  final DateTime at;

  /// 0 fresh, 1 today or yesterday, 2 overdue.
  final int age;
  final double progress;
  final WaitingItem? waiting;
  final TodoItem? todo;
  final MoneyAsk? money;

  const OweLine({
    required this.title,
    required this.meta,
    required this.at,
    this.age = 0,
    this.progress = 0,
    this.waiting,
    this.todo,
    this.money,
  });
}

/// A question of the owner's with nothing back since.
class OwesLine {
  final String asked;
  final String meta;
  final DateTime askedAt;

  /// The thread it was asked in.
  final String thread;

  /// Whether it's old enough to offer a follow-up.
  final bool followUpDue;

  const OwesLine({
    required this.asked,
    required this.meta,
    required this.askedAt,
    required this.thread,
    required this.followUpDue,
  });
}

/// Open loops with one person, both ways.
class PersonLoops {
  final List<OweLine> owe;
  final List<OwesLine> owes;

  const PersonLoops(this.owe, this.owes);

  bool get isEmpty => owe.isEmpty && owes.isEmpty;

  int get oweAge => owe.fold(0, (a, l) => l.age > a ? l.age : a);

  double get oweProgress =>
      owe.fold(0.0, (a, l) => l.progress > a ? l.progress : a);

  /// What's open, for the row and for search.
  String get bits => [
    for (final l in owe) l.title,
    for (final l in owes) l.asked,
  ].join(' · ');
}

/// To-dos older than this no longer count as owed.
const _todoReach = Duration(days: 14);

/// Pairs every open item with its person. Items Echo can't tie to a known
/// person aren't shown here (they still live in To-do and on Today).
///
/// A to-do made from a waiting message replaces it, and a money ask replaces
/// a to-do made from it, so one obligation is one row.
Map<String, PersonLoops> buildLoops({
  required List<MergedPerson> people,
  required List<WaitingItem> waiting,
  required List<TodoItem> todos,
  required List<MoneyAsk> money,
  required MyTurns turns,
  required Map<String, int> openedAt,
  required Map<String, int> snoozedUntil,
  required DateTime now,
}) {
  final rootOf = <String, String>{};
  final byName = <String, Set<String>>{};
  final threadOwner = <String, MergedPerson>{};
  for (final p in people) {
    for (final m in p.members) {
      rootOf[m] = p.key;
    }
    (byName[normalisedName(p.name)] ??= {}).add(p.key);
    for (final e in p.directThreads) {
      threadOwner[e.key] = p;
    }
  }
  String? root(String key) => rootOf[key];

  final owe = <String, List<OweLine>>{};
  final owes = <String, List<OwesLine>>{};

  final moneyKeys = {for (final a in money) a.line.key};
  final today = DateTime(now.year, now.month, now.day);
  final reach = today.subtract(_todoReach);
  final todoKeys = <String>{};
  for (final t in todos) {
    if (t.done || t.typed || t.day.isBefore(reach)) continue;
    final baseKey = t.sourceKey.split('#').first;
    if (moneyKeys.contains(baseKey)) continue;
    final key = _todoPerson(t, rootOf, byName, turns, threadOwner);
    if (key == null) continue;
    todoKeys.add(baseKey);
    (owe[key] ??= []).add(
      OweLine(
        title: t.title,
        meta: '${_dueWord(t, now)} · on your to-do list',
        at: t.created,
        age: t.day.isBefore(today) ? 2 : 0,
        todo: t,
      ),
    );
  }

  for (final w in waiting) {
    if (todoKeys.contains(sourceKeyOf(w.message))) continue;
    final key = root(w.personKey);
    if (key == null) continue;
    final m = w.message;
    final where = m.isGroup && (m.threadTitle?.isNotEmpty ?? false)
        ? ' · in ${m.threadTitle}'
        : '';
    (owe[key] ??= []).add(
      OweLine(
        title: clip(m.content, 90),
        meta: '${w.reason.label} · ${w.since}$where',
        at: m.timestamp,
        age: w.ageBand,
        progress: w.ageProgress,
        waiting: w,
      ),
    );
  }

  for (final a in money) {
    final key = root(personKeyFor(a.line.sender, a.line.source));
    if (key == null) continue;
    final due = a.due;
    final meta = [
      if (due != null) 'By ${dayWord(due, now)}',
      a.line.title.isEmpty ? 'in a group' : a.line.title,
    ].join(' · ');
    (owe[key] ??= []).add(
      OweLine(
        title: a.what == 'a payment' ? 'A payment asked for' : a.what,
        meta: meta,
        at: a.line.at,
        age: due != null && due.isBefore(today) ? 2 : 1,
        money: a,
      ),
    );
  }

  for (final MapEntry(key: thread, value: list) in turns.byThread.entries) {
    final person = threadOwner[thread];
    if (person == null || list.isEmpty) continue;
    final heard = person.threads[thread]?.heardAt ?? 0;
    final open = [
      for (final t in list)
        if (t.at.millisecondsSinceEpoch > heard && OwedStore.isOpenAsk(t, now))
          t,
    ]..sort((a, b) => a.at.compareTo(b.at));
    if (open.isEmpty) continue;
    final oldest = open.first;
    final latest = list.reduce((a, b) => b.at.isAfter(a.at) ? b : a);
    final opened = (openedAt[thread] ?? 0) > oldest.at.millisecondsSinceEpoch;
    final snoozed =
        (snoozedUntil[thread] ?? 0) > now.millisecondsSinceEpoch;
    (owes[person.key] ??= []).add(
      OwesLine(
        asked: clip(oldest.text, 90),
        meta:
            'Asked ${dayWord(oldest.at, now)} · '
            '${opened ? 'you opened the chat since' : 'nothing since'}',
        askedAt: oldest.at,
        thread: thread,
        followUpDue:
            !snoozed && now.difference(latest.at) >= followUpAfter,
      ),
    );
  }

  return {
    for (final key in {...owe.keys, ...owes.keys})
      key: PersonLoops(
        (owe[key] ?? const [])..sort((a, b) => b.age.compareTo(a.age)),
        owes[key] ?? const [],
      ),
  };
}

/// A to-do's person. A message's sender is in its source key; a line the
/// owner wrote is tied to the chat it was written in by its time.
String? _todoPerson(
  TodoItem t,
  Map<String, String> rootOf,
  Map<String, Set<String>> byName,
  MyTurns turns,
  Map<String, MergedPerson> threadOwner,
) {
  final base = t.sourceKey.split('#').first;
  final bar = base.lastIndexOf('|');
  if (bar <= 0) return null;
  final sender = base.substring(0, bar);
  if (sender == 'You') {
    final ms = int.tryParse(base.substring(bar + 1));
    if (ms == null) return null;
    for (final MapEntry(key: thread, value: list) in turns.byThread.entries) {
      if (list.any((x) => x.at.millisecondsSinceEpoch == ms)) {
        return threadOwner[thread]?.key;
      }
    }
    return null;
  }
  final key = rootOf[personKeyFor(sender, t.app)];
  if (key != null) return key;
  // The to-do's app is a display name that can differ from the stored one.
  // A name only one known person has is safe to use instead.
  final same = byName[normalisedName(sender)];
  return same != null && same.length == 1 ? same.first : null;
}

String _dueWord(TodoItem t, DateTime now) {
  final word = dayWord(t.day, now);
  return t.time == null ? cap(word) : '${cap(word)}, ${t.time}';
}

const _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// "today", "yesterday", "tomorrow", "Tuesday", or "9 Nov" further off.
String dayWord(DateTime d, DateTime now) {
  final diff = dayOf(d) - dayOf(now);
  if (diff == 0) return 'today';
  if (diff == -1) return 'yesterday';
  if (diff == 1) return 'tomorrow';
  if (diff.abs() < 7) return _weekdayNames[d.weekday - 1];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${d.day} ${months[d.month - 1]}';
}

String cap(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// [s] on one line, at most [max] characters.
String clip(String s, int max) {
  final t = s.replaceAll('\n', ' ').trim();
  return t.length <= max ? t : '${t.substring(0, max - 1).trimRight()}…';
}
