import 'dart:async';
import 'dart:convert';

import 'package:echo_native/echo_native.dart';
import 'package:flutter/foundation.dart';
import 'package:isar_community/isar.dart';
import 'package:project_echo/core/services/app_icon_service.dart';
import 'package:project_echo/features/echo/data/context/addressed.dart';
import 'package:project_echo/features/echo/data/context/chat_context_store.dart';
import 'package:project_echo/features/vault/data/daily_stats.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/datasources/tflite_embedding_service.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/relevance/briefing_selection.dart';
import 'package:project_echo/features/echo/data/relevance/temporal_relevance.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Moves captured notifications and calendar events into Isar. Uses only the
/// echo_native plugin (no Activity-bound channels), so it runs both in the app
/// and in the background briefing alarm.
///
/// Catching up after days closed is quick: the backlog is saved in one go,
/// without embeddings, and what the Vault would delete anyway (more than a
/// day old and about nothing still ahead) isn't saved at all. Embeddings are
/// made afterwards, newest first ([EmbeddingBackfill]); until then search
/// still finds a message by its words, sender and time.
///
/// The native buffer only lends notifications out: each round is deleted
/// there once it's saved here, so the app dying mid-catch-up loses nothing,
/// and a round delivered again is recognised by its [RawData.captureKey].
/// Every notification is buffered, even while the app is open; the copy
/// delivered live carries the same key, so it's saved once whichever
/// arrives first. Saves run one at a time, never side by side.
class NotificationIngest {
  NotificationIngest._();

  /// The catch-up under way, if any.
  static Future<void>? _draining;

  /// Completes once notifications missed while the app was closed are saved,
  /// so an answer or a briefing covers them. Quick: it doesn't wait for
  /// their embeddings.
  static Future<void> whenCaughtUp() => _draining ?? Future<void>.value();

  /// Saves every notification buffered natively while no UI was listening.
  /// Overlapping calls share one catch-up.
  static Future<void> drainBuffer() =>
      _draining ??= _drain().whenComplete(() => _draining = null);

  static Future<void> _drain() async {
    try {
      await drainRounds(
        peek: () => EchoNative.peekBuffer(limit: _round),
        ack: EchoNative.ackBuffer,
        save: _save,
      );
    } catch (e) {
      debugPrint('Error draining buffer: $e');
    }
  }

  /// Notifications per round of the catch-up. Each round is confirmed once
  /// saved, so a kill mid-catch-up repeats at most one.
  static const _round = 500;

  /// [_drain]'s rounds, with the buffer and the saving passed in for tests.
  /// Each round [peek] lends is saved, then confirmed with [ack]. A round
  /// that won't save is tried one by one: if none of it saves (Isar is
  /// unavailable, say) it stays buffered for next time; otherwise what still
  /// fails is dropped, so one bad notification can't hold up the rest.
  @visibleForTesting
  static Future<void> drainRounds({
    required Future<Map<String, String>> Function() peek,
    required Future<void> Function(Iterable<String> keys) ack,
    required Future<void> Function(List<Map<String, dynamic>> items) save,
  }) async {
    while (true) {
      final lent = await peek();
      if (lent.isEmpty) return;
      final items = <Map<String, dynamic>>[];
      for (final MapEntry(:key, :value) in lent.entries) {
        try {
          final json = jsonDecode(value);
          if (json is Map<String, dynamic>) {
            items.add(json..['captureKey'] = key);
          }
        } catch (_) {
          debugPrint('Dropping an unreadable buffered notification.');
        }
      }
      try {
        await save(items);
      } catch (e) {
        debugPrint('Saving ${items.length} buffered notifications failed: $e');
        var saved = 0;
        for (final item in items) {
          try {
            await save([item]);
            saved++;
          } catch (_) {}
        }
        if (saved == 0 && items.isNotEmpty) return;
      }
      await ack(lent.keys);
    }
  }

  /// Brings the calendar events for today and tomorrow — the briefing's
  /// horizon — in line with the calendar: new occurrences are saved, ones
  /// moved or deleted there are removed, and changed details are updated,
  /// so the briefing never mentions a meeting that's no longer on.
  static Future<void> syncCalendar() async {
    try {
      final now = DateTime.now();
      final from = startOfDay(now);
      final to = briefingHorizonEnd(now);
      final events = jsonDecode(await EchoNative.fetchCalendarEvents(from, to));
      if (events is! List) return;
      final fetched = <String, Map<String, dynamic>>{};
      for (final item in events) {
        if (item is! Map<String, dynamic> || item['timestamp'] is! int) {
          continue;
        }
        final key = calendarKey(
          item['sender'] as String? ?? '',
          item['timestamp'] as int,
        );
        fetched[key] = item..['captureKey'] = key;
      }
      // An event under way since yesterday is fetched too, under its own
      // start, so what's stored is looked up from the earliest start.
      var earliest = from;
      for (final item in fetched.values) {
        final start = _time(item);
        if (start.isBefore(earliest)) earliest = start;
      }
      await _serially(() async {
        final isar = await IsarDataSource.instance;
        final stored = await isar.rawDatas
            .filter()
            .timestampBetween(earliest, to)
            .group(
              (q) => q
                  .captureKeyStartsWith(_calendarPrefix)
                  .or()
                  // Saved before events had a key.
                  .group(
                    (q) => q
                        .sourceEqualTo('Calendar')
                        .threadIsNull()
                        .captureKeyIsNull(),
                  ),
            )
            .findAll();
        final changes = reconcileCalendar(
          stored: [
            for (final e in stored)
              (
                id: e.id,
                key:
                    e.captureKey ??
                    calendarKey(e.sender, e.timestamp.millisecondsSinceEpoch),
                at: e.timestamp,
                content: e.content,
              ),
          ],
          fetched: fetched,
          from: from,
        );
        if (changes.gone.isNotEmpty || changes.changed.isNotEmpty) {
          await isar.writeTxn(() async {
            await isar.rawDatas.deleteAll(changes.gone);
            final current = await isar.rawDatas.getAll([
              for (final c in changes.changed) c.id,
            ]);
            final updated = <RawData>[];
            for (var i = 0; i < current.length; i++) {
              final entry = current[i];
              if (entry == null) continue;
              // Re-embedded with its new details by the backfill.
              updated.add(
                entry
                  ..content = changes.changed[i].content
                  ..embedding = null,
              );
            }
            await isar.rawDatas.putAll(updated);
          });
          debugPrint(
            'Calendar: ${changes.gone.length} events gone, '
            '${changes.changed.length} changed.',
          );
        }
        await _saveNow(changes.fresh);
        if (changes.changed.isNotEmpty) unawaited(EmbeddingBackfill.run());
      });
    } catch (e) {
      debugPrint('Error fetching calendar events: $e');
    }
  }

  static const _calendarPrefix = 'calendar:';

  /// What identifies a calendar occurrence: its title and start, so a daily
  /// standup gets one entry per day, and a meeting moved to another time is
  /// a different one.
  @visibleForTesting
  static String calendarKey(String title, int startMs) =>
      '$_calendarPrefix$startMs:$title';

  /// What [syncCalendar] does with the events [stored] against those the
  /// calendar has now ([fetched], by [calendarKey]): stored ones it no
  /// longer has, starting from [from] on, are [gone] (earlier ones are
  /// history, and the calendar wasn't asked about them); ones whose details
  /// changed are [changed]; and the calendar's others are [fresh]. Repeats
  /// of one occurrence, left by older versions, go too.
  @visibleForTesting
  static ({
    List<int> gone,
    List<({int id, String content})> changed,
    List<Map<String, dynamic>> fresh,
  })
  reconcileCalendar({
    required List<({int id, String key, DateTime at, String content})> stored,
    required Map<String, Map<String, dynamic>> fetched,
    required DateTime from,
  }) {
    final gone = <int>[];
    final changed = <({int id, String content})>[];
    final kept = <String>{};
    for (final e in stored) {
      final now = fetched[e.key];
      if (now == null) {
        if (!e.at.isBefore(from)) gone.add(e.id);
        continue;
      }
      if (!kept.add(e.key)) {
        gone.add(e.id);
        continue;
      }
      final content = now['content'] as String? ?? '';
      if (content != e.content) changed.add((id: e.id, content: content));
    }
    return (
      gone: gone,
      changed: changed,
      fresh: [
        for (final MapEntry(:key, :value) in fetched.entries)
          if (!kept.contains(key)) value,
      ],
    );
  }

  /// Notifications that arrived while the app was open, waiting to be saved.
  static final _live = LiveBatches<Map<String, dynamic>>(_saveLive);

  /// Saves one captured notification as it arrives, while the app is open.
  /// The listener has buffered it as well; once it's saved here it's
  /// confirmed to the buffer by its `captureKey`, and if the drain gets to
  /// the buffered copy first, that key keeps it from being saved twice.
  /// Notifications arriving together are saved together, one batch at a
  /// time.
  static Future<void> process(Map<String, dynamic> json) => _live.add(json);

  static Future<void> _saveLive(List<Map<String, dynamic>> items) async {
    // If this throws, the buffered copies stay for the drain.
    await _save(items);
    final keys = [
      for (final item in items)
        if (item['captureKey'] case final String key) key,
    ];
    if (keys.isNotEmpty) await EchoNative.ackBuffer(keys);
  }

  /// The saving under way; every save waits for the one before it.
  static Future<void> _tail = Future<void>.value();

  /// Runs [task] once every save started before it has finished. Saves read
  /// and rewrite shared counters (the Vault's week, app icons, chat
  /// context), so two at once would lose each other's updates.
  static Future<T> _serially<T>(Future<T> Function() task) {
    final run = _tail.then((_) => task());
    _tail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  /// Keys saved lately by this engine, so a notification both delivered live
  /// and drained from the buffer counts, and signals, once.
  static final _recentKeys = <String>{};
  static const _recentKeysKept = 2000;

  /// Forgets [_recentKeys], as a restart would.
  @visibleForTesting
  static void forgetRecentKeys() => _recentKeys.clear();

  static void _remember(Iterable<String> keys) {
    // Calendar events are kept in line with what's stored instead: one
    // deleted and put back in the calendar is saved again.
    _recentKeys.addAll(keys.where((k) => !k.startsWith(_calendarPrefix)));
    final extra = _recentKeys.length - _recentKeysKept;
    if (extra > 0) _recentKeys.removeAll(_recentKeys.take(extra).toList());
  }

  /// Saves captured notifications and the signals among them (taps, swipes,
  /// the owner's own messages) in a handful of writes, then starts making
  /// their embeddings in the background. Returns how many were saved.
  static Future<int> ingestAll(
    List<Map<String, dynamic>> items, {
    DateTime? now,
  }) async {
    try {
      return await _save(items, now: now);
    } catch (e) {
      debugPrint('Error processing notifications: $e');
      return 0;
    }
  }

  /// [ingestAll], throwing if something can't be saved. Waits for any save
  /// under way.
  static Future<int> _save(List<Map<String, dynamic>> items, {DateTime? now}) =>
      _serially(() => _saveNow(items, now: now));

  /// [_save], for a caller already running [_serially].
  static Future<int> _saveNow(
    List<Map<String, dynamic>> items, {
    DateTime? now,
  }) async {
    final unseen = [
      for (final json in items)
        if (!_recentKeys.contains(json['captureKey'])) json,
    ];
    if (unseen.isEmpty) return 0;
    final at = now ?? DateTime.now();
    final ordered = [...unseen]..sort((a, b) => _time(a).compareTo(_time(b)));

    // Signals first: who the owner is, where they spoke, what they opened.
    final selfNames = <String>{};
    final myTurns = <({String thread, DateTime at, String text})>[];
    final engagements = <({String thread, String action, DateTime at})>[];
    final notifications = <Map<String, dynamic>>[];
    for (final json in ordered) {
      final thread = json['thread'] as String?;
      if (json['kind'] == 'engagement') {
        if (thread != null) {
          engagements.add((
            thread: thread,
            action: json['action'] as String? ?? '',
            at: _time(json),
          ));
        }
        continue;
      }
      final selfName = json['selfName'] as String?;
      if (selfName != null) selfNames.add(selfName);
      // The owner's own message only marks when they last spoke there.
      if (json['fromMe'] == true) {
        if (thread != null) {
          myTurns.add((
            thread: thread,
            at: _time(json),
            text: json['content'] as String? ?? '',
          ));
        }
        continue;
      }
      notifications.add(json);
    }
    await ChatContextStore.learnSelfNames(selfNames);
    await ChatContextStore.recordMyTurns(myTurns);
    await ChatContextStore.recordEngagements(engagements);
    if (notifications.isEmpty) {
      _remember([for (final json in unseen) ?json['captureKey'] as String?]);
      return 0;
    }

    // What every notification needs, read once.
    final prefs = await SharedPreferences.getInstance();
    final aliases = Map<String, String>.from(
      jsonDecode(prefs.getString('vault_category_aliases') ?? '{}'),
    );
    final myNames = ownerNames(
      prefs.getString('user_name'),
      await ChatContextStore.selfNames(),
    );
    final turns = await ChatContextStore.loadMyTurns();
    final isar = await IsarDataSource.instance;

    final keep = <RawData>[];
    final counted = <({String source, DateTime at, String? key})>[];
    final packages = <String, Map<String, int>>{};
    // Per group: messages already saved after the owner last spoke there,
    // and those seen in this batch so far.
    final savedSince = <String, int>{};
    final seenInBatch = <String, List<DateTime>>{};

    for (final json in notifications) {
      final time = _time(json);
      final rawSource = json['source'] as String? ?? 'Unknown';
      final defaultSource = rawSource.isEmpty
          ? 'Unknown'
          : '${rawSource[0].toUpperCase()}${rawSource.substring(1).toLowerCase()}';
      final source = aliases[defaultSource] ?? defaultSource;
      final package = json['packageName'] as String?;
      if (package != null && package.isNotEmpty) {
        final forSource = packages.putIfAbsent(defaultSource, () => {});
        forSource[package] = (forSource[package] ?? 0) + 1;
      }

      final thread = json['thread'] as String?;
      final content = json['content'] as String? ?? '';
      // Only chats say whether they're a group.
      final isChat = json.containsKey('isGroup');
      final isGroup = json['isGroup'] == true;
      Addressed? addressed;
      if (isChat) {
        final spoke = turns.lastBefore(thread, time);
        var since = 0;
        if (isGroup && spoke != null && thread != null) {
          since =
              await _savedSince(isar, savedSince, thread, spoke.at) +
              (seenInBatch[thread] ?? const <DateTime>[])
                  .where((t) => t.isAfter(spoke.at))
                  .length;
        }
        addressed = addressedFor(
          isGroup: isGroup,
          content: content,
          at: time,
          myNames: myNames,
          mySpokeAt: spoke?.at,
          messagesSince: since,
        );
      }
      if (thread != null) {
        seenInBatch.putIfAbsent(thread, () => []).add(time);
      }

      final entry = RawData()
        ..source = source
        ..sender = json['sender'] as String? ?? ''
        ..content = content
        ..timestamp = time
        ..thread = thread
        ..threadTitle = json['threadTitle'] as String?
        ..isGroup = isGroup
        ..addressed = addressed?.name
        ..captureKey = json['captureKey'] as String?;

      // The Vault's week keeps only these numbers, past the Vault's own
      // 24-hour life of a notification, so everything is counted…
      counted.add((source: entry.source, at: time, key: entry.captureKey));
      // …but what the Vault would delete straight away isn't saved.
      if (_stale(entry, at)) continue;
      keep.add(entry);
    }

    var saved = 0;
    final savedBefore = <String>{};
    for (var i = 0; i < keep.length; i += _chunk) {
      final chunk = keep.sublist(i, (i + _chunk).clamp(0, keep.length));
      await isar.writeTxn(() async {
        final fresh = await _unsaved(isar, chunk);
        await isar.rawDatas.putAll(fresh);
        saved += fresh.length;
        if (fresh.length < chunk.length) {
          final freshKeys = {for (final e in fresh) e.captureKey};
          savedBefore.addAll([
            for (final e in chunk)
              if (e.captureKey case final String k when !freshKeys.contains(k))
                k,
          ]);
        }
      });
    }
    // One saved before was counted then.
    await DailyStats.countAll([
      for (final c in counted)
        if (!savedBefore.contains(c.key)) (source: c.source, at: c.at),
    ]);
    await AppIconService.rememberAll(packages);
    debugPrint(
      'Saved $saved of ${notifications.length} notifications '
      '(${notifications.length - keep.length} already past, '
      '${keep.length - saved} saved before).',
    );

    _remember([for (final json in unseen) ?json['captureKey'] as String?]);
    if (saved > 0) unawaited(EmbeddingBackfill.run());
    return saved;
  }

  /// [entries] minus those an earlier, unconfirmed catch-up already saved.
  /// Asked inside the write, so two engines draining at once can't both
  /// save one.
  static Future<List<RawData>> _unsaved(
    Isar isar,
    List<RawData> entries,
  ) async {
    final keys = [for (final e in entries) ?e.captureKey];
    if (keys.isEmpty) return entries;
    final saved =
        (await isar.rawDatas
                .where()
                .anyOf(keys, (q, key) => q.captureKeyEqualTo(key))
                .captureKeyProperty()
                .findAll())
            .toSet();
    return [
      for (final e in entries)
        if (!saved.contains(e.captureKey)) e,
    ];
  }

  /// Saved per Isar transaction.
  static const _chunk = 200;

  /// What [IsarDataSource.deleteOldNotifications] would remove at once: more
  /// than a day old and about nothing still ahead.
  static bool _stale(RawData entry, DateTime now) =>
      entry.timestamp.isBefore(now.subtract(const Duration(hours: 24))) &&
      !isStillRelevant(entry, now);

  static DateTime _time(Map<String, dynamic> json) =>
      DateTime.fromMillisecondsSinceEpoch(
        json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      );

  /// Messages saved in [thread] after the owner last spoke there, asked of
  /// Isar once per thread and moment.
  static Future<int> _savedSince(
    Isar isar,
    Map<String, int> cache,
    String thread,
    DateTime spokeAt,
  ) async {
    final key = '$thread@${spokeAt.millisecondsSinceEpoch}';
    return cache[key] ??= await isar.rawDatas
        .filter()
        .threadEqualTo(thread)
        .timestampGreaterThan(spokeAt)
        .count();
  }
}

/// Hands what's [add]ed to [save] in batches, one batch at a time: what
/// arrives while a batch saves waits, then goes in the next one together. A
/// batch that fails is dropped here (whoever buffered it keeps it).
class LiveBatches<T> {
  LiveBatches(this._save);

  final Future<void> Function(List<T> batch) _save;
  final _waiting = <T>[];
  Future<void>? _running;

  /// Queues [item]; completes once it has been through [_save].
  Future<void> add(T item) {
    _waiting.add(item);
    return _running ??= _run();
  }

  Future<void> _run() async {
    try {
      while (_waiting.isNotEmpty) {
        final batch = [..._waiting];
        _waiting.clear();
        try {
          await _save(batch);
        } catch (e) {
          debugPrint('Saving ${batch.length} live notifications failed: $e');
        }
      }
    } finally {
      _running = null;
    }
  }
}

/// Makes the embeddings saved notifications are still missing, newest first,
/// one at a time — so a question asked meanwhile waits behind one at most.
class EmbeddingBackfill {
  EmbeddingBackfill._();

  static Future<void>? _running;

  /// Starts filling in missing embeddings, or joins the run under way.
  static Future<void> run() =>
      _running ??= _fill().whenComplete(() => _running = null);

  /// Completes once every saved notification has its embedding.
  static Future<void> whenDone() => _running ?? Future<void>.value();

  static const _batch = 20;

  static Future<void> _fill() async {
    try {
      final isar = await IsarDataSource.instance;
      while (true) {
        final missing = await isar.rawDatas
            .filter()
            .embeddingIsNull()
            .sortByTimestampDesc()
            .limit(_batch)
            .findAll();
        if (missing.isEmpty) return;
        for (final entry in missing) {
          final text = '${entry.who} ${entry.content}'.trim();
          // Nothing to embed: an empty vector, so it isn't picked again.
          entry.embedding = text.isEmpty
              ? const []
              : await TfliteEmbeddingService.instance.getEmbedding(text);
        }
        // Only the embedding is written, and only onto entries still there:
        // cleanup may have deleted some meanwhile, and re-saving the whole
        // entry would bring those back (or undo an edit made meanwhile).
        await isar.writeTxn(() async {
          final current = await isar.rawDatas.getAll([
            for (final e in missing) e.id,
          ]);
          final updated = <RawData>[];
          for (var i = 0; i < missing.length; i++) {
            final entry = current[i];
            if (entry == null) continue;
            updated.add(entry..embedding = missing[i].embedding);
          }
          await isar.rawDatas.putAll(updated);
        });
      }
    } catch (e) {
      debugPrint('Embedding backfill stopped: $e');
    }
  }
}
