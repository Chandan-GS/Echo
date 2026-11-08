import 'dart:async';
import 'dart:convert';

import 'package:echo_native/echo_native.dart';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:project_echo/core/services/app_icon_service.dart';
import 'package:project_echo/core/services/retention_settings.dart';
import 'package:project_echo/features/echo/data/context/addressed.dart';
import 'package:project_echo/features/echo/data/context/chat_context_store.dart';
import 'package:project_echo/features/vault/data/daily_stats.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/datasources/tflite_embedding_service.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/relevance/temporal_relevance.dart';
import 'package:project_echo/features/history/data/history_store.dart';
import 'package:project_echo/features/people/data/people_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Moves captured notifications and calendar events into Isar. Uses only the
/// echo_native plugin (no Activity-bound channels), so it runs both in the app
/// and in the background briefing alarm.
///
/// Catching up after days closed is quick: the backlog is saved in one go,
/// without embeddings, and what the cleanup would delete anyway (past the
/// retention setting and about nothing still ahead) isn't saved at all. Embeddings are
/// made afterwards, newest first ([EmbeddingBackfill]); until then search
/// still finds a message by its words, sender and time.
///
/// The native buffer only lends notifications out: each round is deleted
/// there once it's saved here, so the app dying mid-catch-up loses nothing,
/// and a round delivered again is recognised by its [RawData.captureKey].
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

  /// Saves calendar events for today and tomorrow — the briefing's horizon —
  /// skipping occurrences already stored.
  static Future<void> syncCalendar() async {
    try {
      final now = DateTime.now();
      final events = jsonDecode(
        await EchoNative.fetchCalendarEvents(
          startOfDay(now),
          briefingHorizonEnd(now),
        ),
      );
      if (events is! List) return;
      final isar = await IsarDataSource.instance;
      final fresh = <Map<String, dynamic>>[];
      for (final item in events) {
        if (item is! Map<String, dynamic>) continue;
        // Title + start time identifies an occurrence, so a daily standup
        // gets one entry per day rather than being deduplicated away.
        final existing = await isar.rawDatas
            .filter()
            .sourceEqualTo('Calendar')
            .senderEqualTo(item['sender'] as String? ?? '')
            .timestampEqualTo(
              DateTime.fromMillisecondsSinceEpoch(item['timestamp'] as int),
            )
            .count();
        if (existing == 0) fresh.add(item);
      }
      await ingestAll(fresh);
    } catch (e) {
      debugPrint('Error fetching calendar events: $e');
    }
  }

  /// Saves one captured notification (a live one, as it arrives).
  static Future<void> process(Map<String, dynamic> json) => ingestAll([json]);

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

  /// [ingestAll], throwing if something can't be saved.
  static Future<int> _save(
    List<Map<String, dynamic>> items, {
    DateTime? now,
  }) async {
    if (items.isEmpty) return 0;
    final at = now ?? DateTime.now();
    final ordered = [...items]..sort((a, b) => _time(a).compareTo(_time(b)));

    // Signals first: who the owner is, where they spoke, what they opened.
    final selfNames = <String>{};
    final myTurns = <({String thread, DateTime at, String text})>[];
    final engagements = <({String thread, String action, DateTime at})>[];
    final notifications = <Map<String, dynamic>>[];
    final removals = <ShadeRemoval>[];
    for (final json in ordered) {
      if (json['kind'] == 'removal') {
        final removal = ShadeRemoval.fromJson(json);
        if (removal != null) removals.add(removal);
        continue;
      }
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
    await PeopleStore.recordSignals(
      myTurns: myTurns,
      engagements: engagements,
    );
    if (notifications.isEmpty) {
      await HistoryStore.applyRemovals(await IsarDataSource.instance, removals);
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
    final retentionDays = await RetentionSettings.days();

    final keep = <RawData>[];
    final heard = <RawData>[];
    final counted = <({String source, DateTime at})>[];
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
        ..captureKey = json['captureKey'] as String?
        ..noticeKey = json['noticeKey'] as String?
        ..heldAt = json['heldAt'] is int
            ? DateTime.fromMillisecondsSinceEpoch(json['heldAt'] as int)
            : null;

      // The Vault's week keeps only these numbers, past a notification's
      // own life, so everything is counted…
      counted.add((source: entry.source, at: time));
      heard.add(entry);
      // …but what the Vault would delete straight away isn't saved.
      if (IsarDataSource.isExpired(entry, at, retentionDays)) continue;
      keep.add(entry);
    }

    // Before saving: the first tally reads what's already saved.
    await PeopleStore.recordAll(heard);

    var saved = 0;
    for (var i = 0; i < keep.length; i += _chunk) {
      final chunk = keep.sublist(i, (i + _chunk).clamp(0, keep.length));
      await isar.writeTxn(() async {
        final fresh = await _unsaved(isar, chunk);
        await isar.rawDatas.putAll(fresh);
        saved += fresh.length;
      });
    }
    // After the saving: a swipe in this round is about a message saved in it.
    await HistoryStore.applyRemovals(isar, removals);
    await DailyStats.countAll(counted);
    await AppIconService.rememberAll(packages);
    debugPrint(
      'Saved $saved of ${notifications.length} notifications '
      '(${notifications.length - keep.length} already past, '
      '${keep.length - saved} saved before).',
    );

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
        .sentIsNull()
        .count();
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
