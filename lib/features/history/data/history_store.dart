import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:project_echo/core/services/retention_settings.dart';
import 'package:project_echo/features/echo/data/context/addressed.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/relevance/briefing_selection.dart';
import 'package:project_echo/features/vault/data/app_access.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A notification leaving the shade, or a hold that didn't take, as reported
/// by the listener.
class ShadeRemoval {
  final String key;

  /// A [NoticeRemoval] name, or [notHeld].
  final String how;
  final DateTime at;

  const ShadeRemoval(this.key, this.how, this.at);

  /// Quiet hours tried to hold it and the phone wouldn't.
  static const notHeld = 'notHeld';

  static ShadeRemoval? fromJson(Map<String, dynamic> json) {
    final key = json['noticeKey'] as String?;
    final how = json['how'] as String?;
    if (key == null || how == null) return null;
    return ShadeRemoval(
      key,
      how,
      DateTime.fromMillisecondsSinceEpoch(
        json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}

/// One filter above the list, with how many it matches.
class HistoryChip {
  /// 'all', 'you', 'held', 'gone', or 'app:' and the app's name.
  final String id;
  final String label;
  final int count;

  /// The app's name when this is an app's chip.
  final String? source;

  const HistoryChip(this.id, this.label, this.count, {this.source});
}

/// A day's heading in the list.
class HistoryDay {
  final DateTime day;
  final int count;

  /// Where the day's first message is among all the matches.
  final int firstIndex;

  const HistoryDay(this.day, this.count, this.firstIndex);
}

/// What a search and filter come to: enough to lay out the whole list, with
/// the messages themselves read a page at a time.
class HistoryShape {
  final List<HistoryChip> chips;
  final List<HistoryDay> days;
  final int total;

  /// Whether Echo holds anything at all, whatever the filter.
  final bool anything;

  const HistoryShape({
    required this.chips,
    required this.days,
    required this.total,
    required this.anything,
  });

  static const empty = HistoryShape(
    chips: [],
    days: [],
    total: 0,
    anything: false,
  );
}

/// History's reads and writes. Isar does the searching and counting on its
/// own thread, and only the page on screen is ever read in full, so this
/// keeps up with as many notifications as the phone holds.
class HistoryStore {
  HistoryStore._();

  static const pageSize = 40;
  static const shelfLimit = 20;
  static const all = 'all';
  static const toYou = 'you';
  static const held = 'held';
  static const gone = 'gone';

  /// The words of a search, lowercased. A message must contain all of them.
  static List<String> tokens(String text) => text
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toSet()
      .take(6)
      .toList();

  /// Groups [newestFirst] message times under their local days.
  @visibleForTesting
  static List<HistoryDay> daysOf(List<DateTime> newestFirst) {
    final days = <HistoryDay>[];
    DateTime? current;
    var first = 0;
    var count = 0;
    for (var i = 0; i < newestFirst.length; i++) {
      final t = newestFirst[i];
      final day = DateTime(t.year, t.month, t.day);
      if (day != current) {
        if (current != null) days.add(HistoryDay(current, count, first));
        current = day;
        first = i;
        count = 0;
      }
      count++;
    }
    if (current != null) days.add(HistoryDay(current, count, first));
    return days;
  }

  /// Everything to lay the list out for [chip] and [search].
  static Future<HistoryShape> shape(String chip, String search) async {
    final isar = await IsarDataSource.instance;
    final scope = await _Scope.load(isar);
    final words = tokens(search);

    final every = await _query(isar, scope, const []).sourceProperty().findAll();
    if (every.isEmpty) return HistoryShape.empty;
    final found = words.isEmpty
        ? every
        : await _query(isar, scope, words).sourceProperty().findAll();

    final baseCounts = scope.tally(every);
    final foundCounts = scope.tally(found);
    final apps = baseCounts.keys.toList()
      ..sort((a, b) => baseCounts[b]!.compareTo(baseCounts[a]!));

    final youCount = await _forChip(isar, scope, words, toYou).count();
    final heldCount = await _forChip(isar, scope, words, held).count();
    final goneCount = await _forChip(isar, scope, words, gone).count();

    final times = await _forChip(isar, scope, words, chip)
        .sortByTimestampDesc()
        .timestampProperty()
        .findAll();
    return HistoryShape(
      chips: [
        HistoryChip(all, 'All', found.length),
        HistoryChip(toYou, 'To you', youCount),
        HistoryChip(held, 'Held', heldCount),
        HistoryChip(gone, 'Dismissed', goneCount),
        for (final app in apps)
          HistoryChip('app:$app', app, foundCounts[app] ?? 0, source: app),
      ],
      days: daysOf(times),
      total: times.length,
      anything: true,
    );
  }

  /// [pageSize] messages from [offset] of what [chip] and [search] match.
  static Future<List<RawData>> page(
    String chip,
    String search,
    int offset,
  ) async {
    final isar = await IsarDataSource.instance;
    final scope = await _Scope.load(isar);
    return _forChip(isar, scope, tokens(search), chip)
        .sortByTimestampDesc()
        .offset(offset)
        .limit(pageSize)
        .findAll();
  }

  /// What the owner swiped away in the last day, latest first.
  static Future<List<RawData>> recentlySwiped(DateTime now) async {
    final isar = await IsarDataSource.instance;
    final scope = await _Scope.load(isar);
    return _query(isar, scope, const [])
        .swipedAtGreaterThan(now.subtract(const Duration(hours: 24)))
        .sortBySwipedAtDesc()
        .limit(shelfLimit)
        .findAll();
  }

  /// Saves what the owner just sent to [to]'s chat through Echo, as a "you
  /// sent" line. Never fails the send it follows.
  static Future<void> recordSent(RawData to, String text, DateTime at) async {
    try {
      final isar = await IsarDataSource.instance;
      final name = to.isGroup && (to.threadTitle?.isNotEmpty ?? false)
          ? to.threadTitle!
          : to.sender;
      final line = RawData()
        ..source = to.source
        ..sender = 'You to $name'
        ..content = text
        ..timestamp = at
        ..thread = to.thread
        ..threadTitle = to.threadTitle
        // Not one of the group's own messages, so group pages leave it out.
        ..isGroup = false
        ..sent = true;
      await isar.writeTxn(() => isar.rawDatas.put(line));
    } catch (e) {
      debugPrint('Saving a sent reply to History failed: $e');
    }
  }

  /// Marks the messages each of [removals] was carrying. Only messages still
  /// in the shade are touched: apps reuse keys, and an old message that was
  /// read long ago wasn't swiped away just now. Never throws, so a catch-up
  /// isn't held up by it.
  static Future<void> applyRemovals(
    Isar isar,
    List<ShadeRemoval> removals,
  ) async {
    if (removals.isEmpty) return;
    try {
      final keepSwiped = await RetentionSettings.keepSwiped();
      await isar.writeTxn(() async {
        for (final r in removals) {
          final rows = await isar.rawDatas
              .where()
              .noticeKeyEqualTo(r.key)
              .filter()
              .removalIsNull()
              .findAll();
          if (rows.isEmpty) continue;
          if (r.how == ShadeRemoval.notHeld) {
            final marked = [
              for (final row in rows)
                if (row.heldAt != null) row..heldAt = null,
            ];
            await isar.rawDatas.putAll(marked);
          } else if (r.how == NoticeRemoval.swiped && !keepSwiped) {
            await isar.rawDatas.deleteAll([for (final row in rows) row.id]);
          } else {
            for (final row in rows) {
              row.removal = r.how;
              if (r.how == NoticeRemoval.swiped) row.swipedAt = r.at;
            }
            await isar.rawDatas.putAll(rows);
          }
        }
      });
    } catch (e) {
      debugPrint('Marking removed notifications failed: $e');
    }
  }

  static QueryBuilder<RawData, RawData, QAfterFilterCondition> _query(
    Isar isar,
    _Scope scope,
    List<String> words,
  ) => isar.rawDatas
      .filter()
      .optional<QAfterFilterCondition>(
        scope.hidden.isNotEmpty,
        (q) => q.not().group(
          (g) => g.anyOf(
            scope.hidden,
            (b, s) => b.sourceEqualTo(s, caseSensitive: false),
          ),
        ),
      )
      .optional<QAfterFilterCondition>(
        words.isNotEmpty,
        (q) => q.allOf(
          words,
          (b, w) => b.group(
            (g) => g
                .contentContains(w, caseSensitive: false)
                .or()
                .senderContains(w, caseSensitive: false)
                .or()
                .threadTitleContains(w, caseSensitive: false)
                .or()
                .sourceContains(w, caseSensitive: false),
          ),
        ),
      )
      // Calendar events are saved ahead of time; they aren't heard yet.
      .and()
      .timestampLessThan(DateTime.now(), include: true);

  static QueryBuilder<RawData, RawData, QAfterFilterCondition> _forChip(
    Isar isar,
    _Scope scope,
    List<String> words,
    String chip,
  ) {
    final q = _query(isar, scope, words);
    if (chip == toYou) {
      return q.group(
        (g) => g
            .addressedEqualTo(Addressed.direct.name)
            .or()
            .addressedEqualTo(Addressed.mentioned.name)
            .or()
            .addressedEqualTo(Addressed.reply.name),
      );
    }
    if (chip == held) return q.heldAtIsNotNull();
    if (chip == gone) return q.swipedAtIsNotNull();
    if (chip.startsWith('app:')) {
      final raws = scope.rawNames[chip.substring(4)] ?? const <String>{};
      if (raws.isEmpty) return q.sourceEqualTo('\u0000');
      return q.group(
        (g) => g.anyOf(
          raws,
          (b, s) => b.sourceEqualTo(s, caseSensitive: false),
        ),
      );
    }
    return q;
  }
}

/// The owner's category settings, for a query: which saved names are hidden
/// from History, and which saved names each visible app goes by.
class _Scope {
  final Map<String, String> aliases;
  final List<String> hidden;
  final Map<String, Set<String>> rawNames;

  _Scope(this.aliases, this.hidden, this.rawNames);

  static Future<_Scope> load(Isar isar) async {
    final excluded = await loadExcludedSources();
    final prefs = await SharedPreferences.getInstance();
    final aliases = Map<String, String>.from(
      jsonDecode(prefs.getString('vault_category_aliases') ?? '{}'),
    );
    final saved = await isar.rawDatas
        .where()
        .distinctBySource(caseSensitive: false)
        .sourceProperty()
        .findAll();
    final rawNames = <String, Set<String>>{};
    for (final raw in saved) {
      (rawNames[displaySource(raw, aliases)] ??= {}).add(raw);
    }
    return _Scope(aliases, [
      ...excluded,
      for (final MapEntry(:key, :value) in aliases.entries)
        if (excluded.contains(value)) key,
    ], rawNames);
  }

  /// How many of [sources] each app has, by the name shown for it.
  Map<String, int> tally(List<String> sources) {
    final counts = <String, int>{};
    for (final raw in sources) {
      final name = displaySource(raw, aliases);
      counts[name] = (counts[name] ?? 0) + 1;
    }
    return counts;
  }
}
