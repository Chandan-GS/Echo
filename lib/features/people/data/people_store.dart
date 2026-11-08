import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:project_echo/core/services/retention_settings.dart';
import 'package:project_echo/features/echo/data/context/addressed.dart';
import 'package:project_echo/features/echo/data/context/chat_context_store.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/relevance/briefing_selection.dart';
import 'package:project_echo/features/echo/data/waiting/waiting_store.dart';
import 'package:project_echo/features/people/data/birthday_matcher.dart';
import 'package:project_echo/features/people/data/group_rules.dart';
import 'package:project_echo/features/people/data/person_loops.dart';
import 'package:project_echo/features/people/data/person_tally.dart';
import 'package:project_echo/features/todo/data/loop_closer.dart';
import 'package:project_echo/features/todo/data/todo_item.dart';
import 'package:project_echo/features/todo/data/todo_store.dart';
import 'package:project_echo/features/vault/data/app_access.dart';
import 'package:shared_preferences/shared_preferences.dart';

export 'person_tally.dart' show personKeyFor;

/// A birthday on the People tab.
class BirthdayNote {
  final List<String> groups;
  final List<String> wishers;

  /// When the owner wished them, if Echo saw it.
  final DateTime? wishedAt;

  const BirthdayNote({
    required this.groups,
    required this.wishers,
    this.wishedAt,
  });
}

/// One person, as the People tab shows them.
class PersonSummary {
  final String key, name, source;

  /// Messages heard from them so far this week.
  final int weekCount;
  final DateTime? lastAt;

  /// Clearly quieter than usual right now.
  final bool drifting;

  /// Apps they write on, most recent first.
  final List<String> sources;

  /// "Every day", "Most days", "In your groups".
  final String rhythm;
  final Drift? drift;
  final PersonLoops loops;
  final BirthdayNote? birthday;

  const PersonSummary({
    required this.key,
    required this.name,
    required this.source,
    required this.weekCount,
    required this.lastAt,
    required this.drifting,
    this.sources = const [],
    this.rhythm = '',
    this.drift,
    this.loops = const PersonLoops([], []),
    this.birthday,
  });

  /// What search looks through, lower case.
  String get searchText =>
      '$name ${sources.join(' ')} $rhythm ${loops.bits}${birthday != null ? ' birthday' : ''}'
          .toLowerCase();
}

class PeopleFeed {
  final List<PersonSummary> birthdays, drifting, everyone;

  /// People with something open, the longest waiting first.
  final List<PersonSummary> loops;

  const PeopleFeed({
    this.birthdays = const [],
    this.drifting = const [],
    this.everyone = const [],
    this.loops = const [],
  });

  static const empty = PeopleFeed();
}

/// The People tab's numbers and choices. Runs on the phone only: nothing here
/// calls a model or the network.
class PeopleStore {
  PeopleStore._();

  static const tallyKey = 'people_tally_v1';
  static const _seenKey = 'people_seen_capture_v1';
  static const _dontNudgeKey = 'people_dont_nudge_v1';
  static const _noWatchKey = 'people_no_watch_v1';
  static const _driftShownKey = 'people_drift_shown_v1';
  static const _driftNotNowKey = 'people_drift_not_now_v1';
  static const _followUpKey = 'people_followup_snooze_v1';
  static const _paidKey = 'people_paid_v1';
  static const _wishedKey = 'people_wished_v1';
  static const _openedKey = 'people_opened_v1';
  static const _seenMineKey = 'people_seen_mine_v1';
  static const _groupOffKey = 'people_group_off_v1';

  static const _maxSeen = 1500;
  static const _maxPaid = 500;
  static const _driftsShown = 3;

  /// Ticks when a choice changes, so every People screen stays in step.
  static final changed = ValueNotifier<int>(0);

  /// Every change to the tally, one at a time, so concurrent notifications
  /// can't lose each other's counts. Another isolate (the briefing alarm)
  /// is covered by reloading first.
  static Future<void> _tail = Future.value();

  static Future<T> _serial<T>(Future<T> Function() task) {
    final next = _tail.then((_) => task());
    _tail = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  static final _pending = <RawData>[];
  static Future<void>? _flushing;

  /// Counts one message from someone.
  static Future<void> recordMessage(RawData m) => recordAll([m]);

  /// Counts [messages] in one write. Messages that arrive while a write is
  /// under way join the next one, so a busy group stays cheap. Never throws:
  /// the tally must not get in the way of saving a notification.
  static Future<void> recordAll(Iterable<RawData> messages) {
    _pending.addAll(messages.where(isPersonMessage));
    if (_pending.isEmpty) return Future.value();
    return _flushing ??= _flush().whenComplete(() => _flushing = null);
  }

  static Future<void> _flush() async {
    while (_pending.isNotEmpty) {
      final batch = [..._pending];
      _pending.clear();
      try {
        await _serial(() => _apply(batch));
      } catch (e) {
        debugPrint('People tally write failed: $e');
      }
    }
  }

  /// Reads what's been counted so far, filling it in from the messages
  /// already on the phone the first time (an upgrade), before adding
  /// [batch], which isn't saved yet and so can't be counted twice.
  static Future<void> _apply(List<RawData> batch) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final book = TallyBook.decode(prefs.getString(tallyKey));
    await _backfillIfNeeded(book, prefs);
    final now = DateTime.now();
    final fresh = await _notSeenBefore(batch, prefs);
    for (final m in fresh) {
      book.count(m);
    }
    book.prune(now);
    await prefs.setString(tallyKey, book.encode());
  }

  /// A round the native buffer lends twice (the app died before confirming)
  /// keeps its capture keys, so it's counted once.
  static Future<List<RawData>> _notSeenBefore(
    List<RawData> batch,
    SharedPreferences prefs,
  ) async {
    if (batch.every((m) => m.captureKey == null)) return batch;
    final seen = [...?prefs.getStringList(_seenKey)];
    final known = seen.toSet();
    final fresh = <RawData>[];
    for (final m in batch) {
      final key = m.captureKey;
      if (key == null) {
        fresh.add(m);
      } else if (known.add(key)) {
        fresh.add(m);
        seen.add(key);
      }
    }
    await prefs.setStringList(
      _seenKey,
      seen.sublist(seen.length > _maxSeen ? seen.length - _maxSeen : 0),
    );
    return fresh;
  }

  static Future<void> _backfillIfNeeded(
    TallyBook book,
    SharedPreferences prefs,
  ) async {
    if (book.backfilled) return;
    book.backfilled = true;
    try {
      final isar = await IsarDataSource.instance;
      final retained = await isar.rawDatas
          .filter()
          .addressedIsNotNull()
          .findAll();
      for (final m in retained) {
        book.count(m);
      }
      debugPrint('People tally backfilled from ${retained.length} messages.');
    } catch (e) {
      debugPrint('People backfill failed: $e');
    }
  }

  /// Chats opened, and the owner's lines seen in notifications, for a
  /// person's page. Called from the ingest path, in one write.
  static Future<void> recordSignals({
    required List<({String thread, DateTime at, String text})> myTurns,
    required List<({String thread, String action, DateTime at})> engagements,
  }) async {
    if (myTurns.isEmpty && engagements.isEmpty) return;
    try {
      await _serial(() async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        final opened = _intMap(prefs.getString(_openedKey));
        for (final e in engagements) {
          if (e.action != 'opened' && e.action != 'read') continue;
          opened[e.thread] = e.at.millisecondsSinceEpoch;
        }
        await prefs.setString(_openedKey, jsonEncode(_recent(opened)));
        final mine = _lists(prefs.getString(_seenMineKey));
        for (final t in myTurns) {
          final list = mine[t.thread] ??= [];
          list.add(t.at.millisecondsSinceEpoch);
          if (list.length > 5) list.removeAt(0);
        }
        await prefs.setString(_seenMineKey, jsonEncode(mine));
      });
    } catch (e) {
      debugPrint('People signals failed: $e');
    }
  }

  static Map<String, int> _recent(Map<String, int> m) {
    if (m.length <= 400) return m;
    final keys = m.keys.toList()..sort((a, b) => m[b]!.compareTo(m[a]!));
    return {for (final k in keys.take(400)) k: m[k]!};
  }

  static Map<String, int> _intMap(String? raw) {
    try {
      final j = jsonDecode(raw ?? '{}');
      return {
        if (j is Map)
          for (final e in j.entries)
            if (e.value is int) '${e.key}': e.value as int,
      };
    } catch (_) {
      return {};
    }
  }

  static Map<String, List<int>> _lists(String? raw) {
    try {
      final j = jsonDecode(raw ?? '{}');
      return {
        if (j is Map)
          for (final e in j.entries)
            if (e.value is List)
              '${e.key}': [
                for (final v in e.value as List)
                  if (v is int) v,
              ],
      };
    } catch (_) {
      return {};
    }
  }

  /// Whether [source] may be shown: apps the owner excluded never are.
  static Future<bool Function(String)> sourceFilter() async {
    final excluded = await loadExcludedSources();
    if (excluded.isEmpty) return (_) => true;
    final prefs = await SharedPreferences.getInstance();
    final aliases = Map<String, String>.from(
      jsonDecode(prefs.getString('vault_category_aliases') ?? '{}'),
    );
    return (source) => !excluded.contains(displaySource(source, aliases));
  }

  /// The tally, counted up to date, for reading.
  static Future<TallyBook> loadBook() async {
    await _serial(_backfillOnly);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return TallyBook.decode(prefs.getString(tallyKey));
  }

  static Future<void> _backfillOnly() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final book = TallyBook.decode(prefs.getString(tallyKey));
    if (book.backfilled) return;
    await _backfillIfNeeded(book, prefs);
    book.prune(DateTime.now());
    await prefs.setString(tallyKey, book.encode());
  }

  static Future<PeopleFeed> load(DateTime now) async {
    try {
      final book = await loadBook();
      final keep = await sourceFilter();
      final people = mergePeople(book.people, keep: keep);
      final prefs = await SharedPreferences.getInstance();
      final today = dayOf(now);

      final turns = await ChatContextStore.loadMyTurns();
      final lastMine = _lastMineByThread(turns);
      final retention = await RetentionSettings.days();
      final scan = await _scanGroups(
        now.subtract(Duration(days: retention)),
        DateTime(now.year, now.month, now.day),
        now,
        prefs.getStringList(_paidKey)?.toSet() ?? const {},
      );

      final loops = await _loops(people, scan.money, turns, now, prefs);

      final choices = _Choices.read(prefs);
      final week = weekOf(now);
      final summaries = <String, PersonSummary>{};
      for (final p in people) {
        final nudgeable = choices.nudgeable(p.members);
        final mine = _lastMineFor(p, lastMine);
        final drift = nudgeable ? driftOf(p, now, lastMine: mine) : null;
        summaries[p.key] = PersonSummary(
          key: p.key,
          name: p.name,
          source: p.source,
          sources: p.sources,
          weekCount: p.countIn(week),
          lastAt: p.last,
          drifting: drift != null,
          rhythm: rhythmOf(p, now),
          drift: drift,
          loops: loops[p.key] ?? const PersonLoops([], []),
        );
      }

      final myNames = ownerNames(
        prefs.getString('user_name'),
        await ChatContextStore.selfNames(),
      );
      final birthdays = _birthdays(
        scan.wishLines,
        myNames,
        people,
        summaries,
        turns,
        choices,
        now,
      );

      final everyone = summaries.values.toList()
        ..sort((a, b) {
          final pa = a.rhythm == 'In your groups' ? 1 : 0;
          final pb = b.rhythm == 'In your groups' ? 1 : 0;
          if (pa != pb) return pa - pb;
          return b.lastAt!.compareTo(a.lastAt!);
        });

      final drifting =
          summaries.values.where((s) {
            if (s.drift == null) return false;
            final members = _membersOf(people, s.key);
            return choices.driftAllowed(members, today);
          }).toList()..sort(
            (a, b) => b.drift!.silentDays.compareTo(a.drift!.silentDays),
          );

      final open =
          summaries.values.where((s) => !s.loops.isEmpty).toList()..sort((a, b) {
            final age = b.loops.oweAge.compareTo(a.loops.oweAge);
            if (age != 0) return age;
            return (b.loops.owe.length + b.loops.owes.length).compareTo(
              a.loops.owe.length + a.loops.owes.length,
            );
          });

      return PeopleFeed(
        birthdays: birthdays,
        drifting: drifting.take(_driftsShown).toList(),
        everyone: everyone,
        loops: open,
      );
    } catch (e) {
      debugPrint('People feed failed: $e');
      return PeopleFeed.empty;
    }
  }

  static Map<String, DateTime> _lastMineByThread(MyTurns turns) => {
    for (final e in turns.byThread.entries)
      if (e.value.isNotEmpty)
        e.key: e.value.map((t) => t.at).reduce((a, b) => b.isAfter(a) ? b : a),
  };

  static DateTime? _lastMineFor(
    MergedPerson p,
    Map<String, DateTime> lastMine,
  ) {
    DateTime? best;
    for (final thread in p.directThreads) {
      final at = lastMine[thread.key];
      if (at != null && (best == null || at.isAfter(best))) best = at;
    }
    return best;
  }

  static Future<Map<String, PersonLoops>> _loops(
    List<MergedPerson> people,
    List<MoneyAsk> money,
    MyTurns turns,
    DateTime now,
    SharedPreferences prefs,
  ) async {
    final (todos, _) = await TodoStore().load();
    final waiting = await _waiting(now);
    return buildLoops(
      people: people,
      waiting: waiting,
      todos: todos,
      money: money,
      turns: turns,
      openedAt: _intMap(prefs.getString(_openedKey)),
      snoozedUntil: _intMap(prefs.getString(_followUpKey)),
      now: now,
    );
  }

  static Future<List<WaitingItem>> _waiting(DateTime now) async {
    try {
      return (await WaitingStore.load(now)).waiting;
    } catch (e) {
      debugPrint('Waiting feed unavailable: $e');
      return const [];
    }
  }

  /// Everything rules read out of the last few days of group messages, off
  /// the main thread when there's a lot of it.
  static Future<_GroupScan> _scanGroups(
    DateTime since,
    DateTime today,
    DateTime now,
    Set<String> paid,
  ) async {
    final isar = await IsarDataSource.instance;
    final rows = await isar.rawDatas
        .filter()
        .isGroupEqualTo(true)
        .timestampGreaterThan(since)
        .findAll();
    final allowed = await withoutExcludedSources(rows);
    final lines = [for (final e in allowed) GroupLine.of(e)];
    final input = (lines, today, paid);
    return lines.length < 400 ? _scan(input) : compute(_scan, input);
  }

  static List<PersonSummary> _birthdays(
    List<WishLine> lines,
    Iterable<String> ownerNames,
    List<MergedPerson> people,
    Map<String, PersonSummary> summaries,
    MyTurns turns,
    _Choices choices,
    DateTime now,
  ) {
    final sightings = birthdaysFrom(lines, ownerNames: ownerNames);
    if (sightings.isEmpty) return const [];
    final out = <PersonSummary>[];
    final startToday = DateTime(now.year, now.month, now.day);
    for (final s in sightings) {
      final person = _matchBirthday(s, people);
      final known = person == null ? null : summaries[person.key];
      final name = known?.name ?? s.name;
      final key = known?.key ?? personKeyFor(s.name, _sourceOfWish(lines, s));
      final wishedAt =
          choices.wishedAt(key, now.year) ??
          _wishedInTurns(person, s, turns, startToday);
      out.add(
        PersonSummary(
          key: key,
          name: name,
          source: known?.source ?? _sourceOfWish(lines, s),
          sources: known?.sources ?? const [],
          weekCount: known?.weekCount ?? 0,
          lastAt: known?.lastAt,
          drifting: false,
          rhythm: known?.rhythm ?? '',
          loops: known?.loops ?? const PersonLoops([], []),
          birthday: BirthdayNote(
            groups: s.groups,
            wishers: s.wishers,
            wishedAt: wishedAt,
          ),
        ),
      );
    }
    return out;
  }

  /// The group a sighting came from has a known sender for its source.
  static String _sourceOfWish(List<WishLine> lines, BirthdaySighting s) {
    for (final l in lines) {
      if (s.groups.contains(l.group)) return l.source;
    }
    return '';
  }

  /// A birthday's person: someone heard in one of the groups it was
  /// wished in, or otherwise the only person with that first name. Two
  /// people sharing a name with no group to tell them apart stay unknown.
  static MergedPerson? _matchBirthday(
    BirthdaySighting s,
    List<MergedPerson> people,
  ) {
    final key = birthdayKey(s.name);
    final same = [
      for (final p in people)
        if (birthdayKey(p.name) == key) p,
    ];
    if (same.isEmpty) return null;
    final inGroup = [
      for (final p in same)
        if (p.groupThreads.any((t) => s.groups.contains(t.value.title))) p,
    ];
    if (inGroup.length == 1) return inGroup.single;
    return same.length == 1 ? same.single : null;
  }

  static DateTime? _wishedInTurns(
    MergedPerson? person,
    BirthdaySighting s,
    MyTurns turns,
    DateTime startToday,
  ) {
    if (person == null) return null;
    for (final t in person.threads.keys) {
      for (final mine in turns.byThread[t] ?? const <MyTurn>[]) {
        if (!mine.at.isBefore(startToday) && isWishText(mine.text)) {
          return mine.at;
        }
      }
    }
    return null;
  }

  static List<String> _membersOf(List<MergedPerson> people, String key) {
    for (final p in people) {
      if (p.key == key) return p.members;
    }
    return [key];
  }

  static Future<List<String>> _members(String key) async {
    final book = await loadBook();
    final people = mergePeople(book.people);
    for (final p in people) {
      if (p.members.contains(key)) return p.members;
    }
    return [key];
  }

  /// [key] resolved to the person it's now part of, and their whole record.
  static Future<MergedPerson?> person(String key) async {
    final book = await loadBook();
    final keep = await sourceFilter();
    for (final p in mergePeople(book.people, keep: keep)) {
      if (p.key == key || p.members.contains(key)) return p;
    }
    return null;
  }

  static Future<void> setDontNudge(String key, bool on) =>
      _setFlag(_dontNudgeKey, key, on);

  static Future<void> setWatching(String key, bool on) =>
      _setFlag(_noWatchKey, key, !on);

  static Future<void> _setFlag(String flag, String key, bool on) async {
    final members = await _members(key);
    await _serial(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final set = {...?prefs.getStringList(flag)};
      if (on) {
        set.add(members.first);
      } else {
        set.removeAll(members);
      }
      await prefs.setStringList(flag, set.toList());
    });
    changed.value++;
  }

  /// The drift card stays where it is today, then not for a week.
  static Future<void> markDriftShown(Iterable<String> keys, DateTime now) async {
    final today = dayOf(now);
    await _serial(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final shown = _intMap(prefs.getString(_driftShownKey));
      var dirty = false;
      for (final k in keys) {
        if (shown[k] == today) continue;
        if (!mayShowDrift(shown[k], today)) continue;
        shown[k] = today;
        dirty = true;
      }
      if (dirty) await prefs.setString(_driftShownKey, jsonEncode(shown));
    });
  }

  /// "Not now": gone for a week.
  static Future<void> driftNotNow(String key, DateTime now) async {
    await _serial(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final notNow = _intMap(prefs.getString(_driftNotNowKey));
      notNow[key] = dayOf(now);
      await prefs.setString(_driftNotNowKey, jsonEncode(notNow));
    });
    changed.value++;
  }

  /// "Not now" on a follow-up: it asks again on Monday.
  static Future<void> followUpNotNow(String thread, DateTime now) async {
    await _serial(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final snoozed = _intMap(prefs.getString(_followUpKey));
      snoozed[thread] = nextMonday(now).millisecondsSinceEpoch;
      await prefs.setString(_followUpKey, jsonEncode(snoozed));
    });
    changed.value++;
  }

  /// Remembers a wish sent through Echo. It wouldn't survive in the turns
  /// store past three more messages in that chat.
  static Future<void> markWished(String key, DateTime at) async {
    await _serial(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final wished = _intMap(prefs.getString(_wishedKey));
      wished['$key@${at.year}'] = at.millisecondsSinceEpoch;
      await prefs.setString(_wishedKey, jsonEncode(wished));
    });
    changed.value++;
  }

  /// Closes a group's money ask, and its to-do if one was made from it.
  static Future<void> markPaid(String lineKey, DateTime now) async {
    await _serial(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final paid = [...?prefs.getStringList(_paidKey)];
      if (!paid.contains(lineKey)) paid.add(lineKey);
      await prefs.setStringList(
        _paidKey,
        paid.sublist(paid.length > _maxPaid ? paid.length - _maxPaid : 0),
      );
    });
    await markTodo(lineKey, now);
    changed.value++;
  }

  /// Ticks off every to-do made from the message with this source key.
  static Future<void> markTodo(String lineKey, DateTime now) async {
    final store = TodoStore();
    final (items, meta) = await store.load();
    final ticked = <TodoItem>[];
    final next = [
      for (final i in items)
        if (!i.done && i.sourceKey.split('#').first == lineKey)
          () {
            final t = i.withDone(true, now);
            ticked.add(t);
            return t;
          }()
        else
          i,
    ];
    if (ticked.isEmpty) return;
    await store.save(next, meta);
    TodoStore.changed.value++;
    for (final t in ticked) {
      await LoopCloser.closed(t, true);
    }
  }

  /// Ticks one to-do off from a person's page.
  static Future<void> tickTodo(TodoItem item, DateTime now) async {
    final store = TodoStore();
    final (items, meta) = await store.load();
    final next = [
      for (final i in items)
        if (i.id == item.id) i.withDone(true, now) else i,
    ];
    await store.save(next, meta);
    TodoStore.changed.value++;
    await LoopCloser.closed(item, true);
    changed.value++;
  }

  static Future<Set<String>> paidKeys() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_paidKey)?.toSet() ?? const {};
  }

  static Future<Map<String, List<int>>> seenMine() async {
    final prefs = await SharedPreferences.getInstance();
    return _lists(prefs.getString(_seenMineKey));
  }

  static Future<PersonChoices> choicesFor(List<String> members) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final c = _Choices.read(prefs);
    return PersonChoices(
      dontNudge: c.dontNudge.any(members.contains),
      watching: !c.noWatch.any(members.contains),
    );
  }

  static Future<bool> groupPullsOut(String title) async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getStringList(_groupOffKey)?.contains(title) ?? false);
  }

  static Future<void> setGroupPullsOut(String title, bool on) async {
    final prefs = await SharedPreferences.getInstance();
    final set = {...?prefs.getStringList(_groupOffKey)};
    on ? set.remove(title) : set.add(title);
    await prefs.setStringList(_groupOffKey, set.toList());
    changed.value++;
  }
}

/// The two switches on a person's page.
class PersonChoices {
  final bool dontNudge;
  final bool watching;
  const PersonChoices({required this.dontNudge, required this.watching});
}

class _Choices {
  final Set<String> dontNudge;
  final Set<String> noWatch;
  final Map<String, int> shown;
  final Map<String, int> notNow;
  final Map<String, int> wished;

  const _Choices({
    required this.dontNudge,
    required this.noWatch,
    required this.shown,
    required this.notNow,
    required this.wished,
  });

  factory _Choices.read(SharedPreferences prefs) => _Choices(
    dontNudge: {...?prefs.getStringList(PeopleStore._dontNudgeKey)},
    noWatch: {...?prefs.getStringList(PeopleStore._noWatchKey)},
    shown: PeopleStore._intMap(prefs.getString(PeopleStore._driftShownKey)),
    notNow: PeopleStore._intMap(prefs.getString(PeopleStore._driftNotNowKey)),
    wished: PeopleStore._intMap(prefs.getString(PeopleStore._wishedKey)),
  );

  bool nudgeable(List<String> members) =>
      !members.any(dontNudge.contains) && !members.any(noWatch.contains);

  bool driftAllowed(List<String> members, int today) {
    for (final m in members) {
      final dismissed = notNow[m];
      if (dismissed != null && today - dismissed < 7) return false;
      if (!mayShowDrift(shown[m], today)) return false;
    }
    return true;
  }

  DateTime? wishedAt(String key, int year) {
    final ms = wished['$key@$year'];
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }
}

class _GroupScan {
  final List<MoneyAsk> money;
  final List<WishLine> wishLines;
  const _GroupScan(this.money, this.wishLines);
}

_GroupScan _scan((List<GroupLine>, DateTime, Set<String>) input) {
  final (lines, today, paid) = input;
  final money = <MoneyAsk>[];
  final wishes = <WishLine>[];
  for (final line in lines) {
    if (!line.at.isBefore(today) && line.title.isNotEmpty) {
      wishes.add(
        WishLine(
          sender: line.sender,
          text: line.text,
          at: line.at,
          group: line.title,
          source: line.source,
        ),
      );
    }
    if (paid.contains(line.key)) continue;
    if (skipKindOf(line.text) != null) continue;
    final ask = moneyAskIn(line);
    if (ask != null) money.add(ask);
  }
  return _GroupScan(money, wishes);
}
