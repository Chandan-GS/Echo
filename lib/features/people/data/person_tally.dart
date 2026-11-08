import 'dart:convert';

import 'package:project_echo/features/echo/data/models/raw_data.dart';

/// How many weeks of counts are kept for each person. Counts only, so this
/// outlives the messages themselves, which go after a few days.
const tallyWeeks = 12;

/// People kept in the tally; the longest silent go first past this.
const tallyMaxPeople = 800;

/// Threads remembered per person, for the group list and for replying.
const _threadsPerPerson = 6;

/// A stable key for a person on one app: "whatsapp|rohan sharma". Only the
/// spelling is normalised (case, spaces, emoji, the "~" WhatsApp puts on
/// unsaved names); nothing here decides two names are the same person.
String personKeyFor(String sender, String source) =>
    '${source.trim().toLowerCase()}|${normalisedName(sender)}';

final _nameJunk = RegExp(r'[^\p{L}\p{N}\p{M}\s]', unicode: true);
final _spaces = RegExp(r'\s+');
final _notDigit = RegExp(r'[^0-9]');
final _phoneish = RegExp(r'^[+\d][\d\s().-]{6,}$');

String normalisedName(String sender) {
  final raw = sender.trim().toLowerCase();
  if (_phoneish.hasMatch(raw)) return raw.replaceAll(_notDigit, '');
  final clean = raw
      .replaceAll(_nameJunk, ' ')
      .replaceAll('️', '')
      .replaceAll(_spaces, ' ')
      .trim();
  return clean.isEmpty ? raw : clean;
}

bool isPhoneName(String name) => _phoneish.hasMatch(name.trim());

/// The first word of a name, for "Message Neha". A phone number stays whole.
String firstNameOf(String name) {
  final t = name.trim();
  if (t.isEmpty || isPhoneName(t)) return t;
  return t.split(_spaces).first;
}

/// Local calendar day as a whole number, so daylight saving and travel can't
/// split or double a day.
int dayOf(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 86400000;

/// Weeks counted from a Monday. Day 0 (1 Jan 1970) was a Thursday.
int weekOf(DateTime d) => (dayOf(d) + 3) ~/ 7;

/// The Monday that starts the week after [now], at midnight.
DateTime nextMonday(DateTime now) {
  final days = 8 - now.weekday;
  return DateTime(now.year, now.month, now.day + days);
}

/// How far through its week [now] is, from 0 to 1.
double _weekGone(DateTime now) =>
    ((now.weekday - 1) + (now.hour + now.minute / 60) / 24) / 7;

final _botName = RegExp(r'\bbot\b|slackbot', caseSensitive: false);

/// Whether [m] is a chat message from a real person. Anything an app posts
/// for itself (a group's own notices, the owner's lines, bots) isn't one.
bool isPersonMessage(RawData m) {
  if (m.addressed == null) return false;
  final name = m.sender.trim();
  if (name.isEmpty || name.toLowerCase() == 'you') return false;
  if (name.toLowerCase() == m.source.trim().toLowerCase()) return false;
  if (m.isGroup && name == m.threadTitle) return false;
  if (_botName.hasMatch(name)) return false;
  return true;
}

/// One chat a person has been heard in.
class HeardThread {
  int heardAt;
  bool isGroup;
  String? title;

  HeardThread(this.heardAt, this.isGroup, this.title);

  List<Object?> toJson() => [heardAt, isGroup ? 1 : 0, title];

  static HeardThread? fromJson(Object? j) {
    if (j is! List || j.length < 2 || j[0] is! int) return null;
    return HeardThread(
      j[0] as int,
      j[1] == 1,
      j.length > 2 ? j[2] as String? : null,
    );
  }
}

/// What Echo keeps about one sender on one app.
class PersonTally {
  String name;
  String source;

  /// Week first heard from.
  int firstWeek;

  /// Messages per week that were meant for the owner: one-to-one, or naming
  /// or answering them in a group. This is what drift is judged on.
  final Map<int, int> direct;

  /// Other messages per week in groups the owner is in.
  final Map<int, int> group;

  int lastAt;
  int? lastDirectAt;
  final Map<String, HeardThread> threads;

  PersonTally({
    required this.name,
    required this.source,
    required this.firstWeek,
    required this.lastAt,
    this.lastDirectAt,
    Map<int, int>? direct,
    Map<int, int>? group,
    Map<String, HeardThread>? threads,
  }) : direct = direct ?? {},
       group = group ?? {},
       threads = threads ?? {};

  void count(RawData m) {
    final week = weekOf(m.timestamp);
    final at = m.timestamp.millisecondsSinceEpoch;
    if (week < firstWeek) firstWeek = week;
    final meant = !m.isGroup || m.addressed != 'group';
    final book = meant ? direct : group;
    book[week] = (book[week] ?? 0) + 1;
    if (at >= lastAt) {
      lastAt = at;
      name = m.sender.trim();
    }
    if (!m.isGroup && at > (lastDirectAt ?? 0)) lastDirectAt = at;
    final thread = m.thread;
    if (thread == null) return;
    final seen = threads[thread];
    if (seen == null) {
      threads[thread] = HeardThread(at, m.isGroup, m.threadTitle);
      _trimThreads();
    } else {
      if (at > seen.heardAt) seen.heardAt = at;
      if (m.threadTitle?.isNotEmpty ?? false) seen.title = m.threadTitle;
    }
  }

  void _trimThreads() {
    if (threads.length <= _threadsPerPerson) return;
    final oldest = threads.keys.toList()
      ..sort((a, b) => threads[a]!.heardAt.compareTo(threads[b]!.heardAt));
    for (final k in oldest.take(threads.length - _threadsPerPerson)) {
      threads.remove(k);
    }
  }

  void prune(int currentWeek) {
    final cut = currentWeek - tallyWeeks + 1;
    direct.removeWhere((w, _) => w < cut);
    group.removeWhere((w, _) => w < cut);
  }

  bool get isEmpty => direct.isEmpty && group.isEmpty;

  Map<String, Object?> toJson() => {
    'n': name,
    's': source,
    'f': firstWeek,
    'd': {for (final e in direct.entries) '${e.key}': e.value},
    'g': {for (final e in group.entries) '${e.key}': e.value},
    'l': lastAt,
    'ld': lastDirectAt,
    't': {for (final e in threads.entries) e.key: e.value.toJson()},
  };

  static Map<int, int> _weeks(Object? j) => {
    if (j is Map)
      for (final e in j.entries)
        if (int.tryParse('${e.key}') != null && e.value is int)
          int.parse('${e.key}'): e.value as int,
  };

  static PersonTally? fromJson(Object? j) {
    if (j is! Map || j['n'] is! String || j['l'] is! int) return null;
    final raw = j['t'];
    return PersonTally(
      name: j['n'] as String,
      source: (j['s'] as String?) ?? '',
      firstWeek: (j['f'] as int?) ?? 0,
      lastAt: j['l'] as int,
      lastDirectAt: j['ld'] as int?,
      direct: _weeks(j['d']),
      group: _weeks(j['g']),
      threads: {
        if (raw is Map)
          for (final e in raw.entries)
            '${e.key}': ?HeardThread.fromJson(e.value),
      },
    );
  }
}

/// Everyone Echo has counted, by [personKeyFor] key.
class TallyBook {
  final Map<String, PersonTally> people;

  /// Whether messages already on the phone at upgrade have been counted.
  /// In the same JSON as the counts, so the two can't disagree.
  bool backfilled;

  TallyBook({Map<String, PersonTally>? people, this.backfilled = false})
    : people = people ?? {};

  void count(RawData m) {
    if (!isPersonMessage(m)) return;
    final key = personKeyFor(m.sender, m.source);
    (people[key] ??= PersonTally(
      name: m.sender.trim(),
      source: m.source,
      firstWeek: weekOf(m.timestamp),
      lastAt: 0,
    )).count(m);
  }

  /// Drops weeks past [tallyWeeks], people with none left, and the longest
  /// silent past [tallyMaxPeople].
  void prune(DateTime now) {
    final week = weekOf(now);
    for (final p in people.values) {
      p.prune(week);
    }
    people.removeWhere((_, p) => p.isEmpty);
    if (people.length <= tallyMaxPeople) return;
    final oldest = people.keys.toList()
      ..sort((a, b) => people[a]!.lastAt.compareTo(people[b]!.lastAt));
    for (final k in oldest.take(people.length - tallyMaxPeople)) {
      people.remove(k);
    }
  }

  String encode() => jsonEncode({
    'b': backfilled,
    'p': {for (final e in people.entries) e.key: e.value.toJson()},
  });

  static TallyBook decode(String? raw) {
    if (raw == null || raw.isEmpty) return TallyBook();
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return TallyBook();
      final p = j['p'];
      return TallyBook(
        backfilled: j['b'] == true,
        people: {
          if (p is Map)
            for (final e in p.entries)
              '${e.key}': ?PersonTally.fromJson(e.value),
        },
      );
    } catch (_) {
      return TallyBook();
    }
  }
}

/// One person after duplicates are merged.
class MergedPerson {
  /// The merged group's key: stable for as long as its members are.
  final String key;
  final List<String> members;
  final String name;

  /// Apps they write on, most recent first.
  final List<String> sources;
  final Map<int, int> direct;
  final Map<int, int> group;
  final int firstWeek;
  final int lastAt;
  final int? lastDirectAt;
  final Map<String, HeardThread> threads;

  const MergedPerson({
    required this.key,
    required this.members,
    required this.name,
    required this.sources,
    required this.direct,
    required this.group,
    required this.firstWeek,
    required this.lastAt,
    required this.lastDirectAt,
    required this.threads,
  });

  String get source => sources.isEmpty ? '' : sources.first;

  DateTime get last => DateTime.fromMillisecondsSinceEpoch(lastAt);

  bool get hasDirect => direct.isNotEmpty;

  int countIn(int week) => (direct[week] ?? 0) + (group[week] ?? 0);

  /// Their one-to-one threads, most recently heard first.
  List<MapEntry<String, HeardThread>> get directThreads => threads.entries
      .where((e) => !e.value.isGroup)
      .toList()
    ..sort((a, b) => b.value.heardAt.compareTo(a.value.heardAt));

  List<MapEntry<String, HeardThread>> get groupThreads => threads.entries
      .where((e) => e.value.isGroup)
      .toList()
    ..sort((a, b) => b.value.heardAt.compareTo(a.value.heardAt));
}

/// Folds duplicates together, only on evidence:
///
/// - the same one-to-one thread under two names (they renamed themselves),
///   unless the thread has three or more names, which means a group the app
///   didn't flag as one;
/// - the same full name, two words or more, on different apps.
///
/// One first name on two apps is two people, and so are "Rohan" and "Rohan
/// Sharma" on one app: a duplicate row is a smaller mistake than someone's
/// messages shown under the wrong person.
List<MergedPerson> mergePeople(
  Map<String, PersonTally> people, {
  bool Function(String source)? keep,
}) {
  final accounts = {
    for (final e in people.entries)
      if (keep == null || keep(e.value.source)) e.key: e.value,
  };
  final parent = {for (final k in accounts.keys) k: k};
  String find(String k) {
    var r = k;
    while (parent[r] != r) {
      r = parent[r]!;
    }
    parent[k] = r;
    return r;
  }

  void union(String a, String b) {
    final ra = find(a), rb = find(b);
    if (ra == rb) return;
    // The alphabetically first key wins, so the result doesn't depend on
    // map order.
    if (ra.compareTo(rb) < 0) {
      parent[rb] = ra;
    } else {
      parent[ra] = rb;
    }
  }

  final byThread = <String, List<String>>{};
  final byFullName = <String, List<String>>{};
  for (final MapEntry(:key, :value) in accounts.entries) {
    for (final t in value.threads.entries) {
      if (!t.value.isGroup) (byThread[t.key] ??= []).add(key);
    }
    if (isPhoneName(value.name)) continue;
    final name = normalisedName(value.name);
    if (name.split(' ').length >= 2) (byFullName[name] ??= []).add(key);
  }
  for (final keys in byThread.values) {
    if (keys.length == 2) union(keys[0], keys[1]);
  }
  for (final keys in byFullName.values) {
    for (final k in keys.skip(1)) {
      union(keys.first, k);
    }
  }

  final groups = <String, List<String>>{};
  for (final k in accounts.keys) {
    (groups[find(k)] ??= []).add(k);
  }
  return [
    for (final MapEntry(key: root, value: members) in groups.entries)
      _merge(root, members, accounts),
  ];
}

MergedPerson _merge(
  String root,
  List<String> members,
  Map<String, PersonTally> accounts,
) {
  final list = [for (final k in members) accounts[k]!]
    ..sort((a, b) => b.lastAt.compareTo(a.lastAt));
  // A name beats a phone number, a longer name a shorter one; ties go to
  // the most recent spelling.
  var best = list.first.name;
  for (final t in list.skip(1)) {
    final phoneWorse = isPhoneName(best) && !isPhoneName(t.name);
    final longer =
        isPhoneName(best) == isPhoneName(t.name) &&
        t.name.length > best.length;
    if (phoneWorse || longer) best = t.name;
  }
  final direct = <int, int>{};
  final group = <int, int>{};
  final threads = <String, HeardThread>{};
  int? lastDirect;
  var first = list.first.firstWeek;
  final sources = <String>[];
  for (final t in list) {
    t.direct.forEach((w, c) => direct[w] = (direct[w] ?? 0) + c);
    t.group.forEach((w, c) => group[w] = (group[w] ?? 0) + c);
    threads.addAll(t.threads);
    if (t.firstWeek < first) first = t.firstWeek;
    final ld = t.lastDirectAt;
    if (ld != null && (lastDirect == null || ld > lastDirect)) lastDirect = ld;
    if (!sources.contains(t.source)) sources.add(t.source);
  }
  return MergedPerson(
    key: root,
    members: members,
    name: best,
    sources: sources,
    direct: direct,
    group: group,
    firstWeek: first,
    lastAt: list.first.lastAt,
    lastDirectAt: lastDirect,
    threads: threads,
  );
}

/// The rhythm of a person who has gone quieter than usual.
class Drift {
  /// What Echo saw: "Usually every day. No messages in 6 days."
  final String line;

  /// Messages per week, oldest first; the last [low] are the quiet ones.
  final List<int> bars;
  final int low;
  final int silentDays;

  /// How overdue, 0 to 1, for the avatar ring.
  final double progress;

  const Drift({
    required this.line,
    required this.bars,
    required this.low,
    required this.silentDays,
    required this.progress,
  });
}

/// Weeks that must have passed since a person was first heard from before
/// Echo says anything about them going quiet.
const driftMinHistoryWeeks = 3;

/// Recent weeks at or below this share of the usual are "clearly below".
const _driftShare = 0.4;

/// Whether someone has gone clearly quieter than their own rhythm, or null.
///
/// Only messages meant for the owner count, and only someone with at least
/// [driftMinHistoryWeeks] of history and a real habit of writing. Recent
/// means last week plus this week so far, so Monday morning isn't "silent".
/// The silence must also be long for that person: anyone who goes quiet for
/// weeks and comes back is judged by their own longest gap.
///
/// Echo can't see calls or time together, and [lastMine] (the owner's own
/// latest message to them) vetoes it.
Drift? driftOf(MergedPerson p, DateTime now, {DateTime? lastMine}) {
  final last = p.lastDirectAt;
  if (last == null) return null;
  final week = weekOf(now);
  if (week - p.firstWeek + 1 < driftMinHistoryWeeks) return null;

  final from = p.firstWeek > week - tallyWeeks + 1
      ? p.firstWeek
      : week - tallyWeeks + 1;
  final baseline = [for (var w = from; w <= week - 2; w++) p.direct[w] ?? 0];
  if (baseline.isEmpty) return null;
  final total = baseline.fold<int>(0, (a, b) => a + b);
  final active = baseline.where((c) => c > 0).length;
  if (total < 6 || active < (baseline.length < 3 ? baseline.length : 3)) {
    return null;
  }
  final usual = total / baseline.length;
  if (usual < 1) return null;

  final recent =
      ((p.direct[week - 1] ?? 0) + (p.direct[week] ?? 0)) /
      (1 + _weekGone(now));
  if (recent > usual * _driftShare) return null;

  var run = 0, longestRun = 0;
  for (final c in baseline) {
    run = c == 0 ? run + 1 : 0;
    if (run > longestRun) longestRun = run;
  }
  final silent = now
      .difference(DateTime.fromMillisecondsSinceEpoch(last))
      .inHours / 24;
  final expected = (7 / usual).clamp(1, 14).toDouble();
  var needed = expected * 3;
  if (needed < 5) needed = 5;
  final ownGap = (longestRun + 1) * 7.0;
  if (longestRun > 0 && needed < ownGap) needed = ownGap;
  if (silent < needed) return null;
  if (lastMine != null &&
      now.difference(lastMine) < const Duration(days: 5)) {
    return null;
  }

  final silentDays = silent.floor();
  final bars = [
    for (var w = (week - 7 < p.firstWeek ? p.firstWeek : week - 7);
        w <= week;
        w++)
      p.direct[w] ?? 0,
  ];
  var low = 0;
  for (final c in bars.reversed) {
    if (c > usual * _driftShare) break;
    low++;
  }
  return Drift(
    line: _driftLine(usual, silentDays),
    bars: bars,
    low: low,
    silentDays: silentDays,
    progress: ((silent - needed) / needed).clamp(0.15, 1).toDouble(),
  );
}

String _driftLine(double usual, int silentDays) {
  final rhythm = usual >= 5
      ? 'every day'
      : usual >= 2.5
      ? 'most days'
      : 'every week';
  final gap = silentDays >= 21
      ? '${(silentDays / 7).round()} weeks'
      : '$silentDays days';
  return silentDays >= 21
      ? 'Used to be $rhythm. No messages in $gap.'
      : 'Usually $rhythm. No messages in $gap.';
}

/// "Every day", "Most days", "Every week", "Now and then", from what they
/// usually send. Someone only ever heard in groups is labelled that way.
String rhythmOf(MergedPerson p, DateTime now) {
  if (!p.hasDirect) return 'In your groups';
  final week = weekOf(now);
  if (p.firstWeek >= week) return 'New this week';
  final from = week - 8 < p.firstWeek ? p.firstWeek : week - 8;
  final weeks = [for (var w = from; w < week; w++) p.direct[w] ?? 0];
  final mean = weeks.fold<int>(0, (a, b) => a + b) / weeks.length;
  if (mean >= 5) return 'Every day';
  if (mean >= 2.5) return 'Most days';
  if (mean >= 1) return 'Every week';
  return 'Now and then';
}

/// Whether a person brought up on [shownDay] may be shown on [today]: the
/// same day it first appeared, or a full week or more after.
bool mayShowDrift(int? shownDay, int today) =>
    shownDay == null || today == shownDay || today - shownDay >= 7;
