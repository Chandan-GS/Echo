import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:project_echo/core/services/gemini_json.dart';
import 'package:project_echo/features/echo/data/context/chat_context_store.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/datasources/priority_query_embedding.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/relevance/briefing_selection.dart';
import 'package:project_echo/features/echo/data/relevance/temporal_relevance.dart';
import 'package:project_echo/features/todo/data/todo_item.dart';
import 'package:project_echo/features/todo/data/todo_planner.dart';
import 'package:project_echo/features/todo/data/todo_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_echo/features/vault/data/app_access.dart';
import 'package:project_echo/features/echo/data/services/notification_ingest.dart';
import 'package:project_echo/demo/demo_mode.dart';

/// Makes and updates the to-do list. Only on request — a briefing never does
/// this by itself.
///
/// Make: the notifications the briefing would cover (now → end of tomorrow)
/// go to Gemini, which replies with short titles pointing at them.
/// Update: only notifications that arrived since the list was last made or
/// updated go in, with one line per open item so a change ("demo pushed to
/// 7 PM") amends that item instead of adding a duplicate. Nothing is ever
/// removed. Without the cloud engine, titles come from the notifications
/// themselves.
class TodoGenerator {
  final TodoStore store;
  TodoGenerator({TodoStore? store}) : store = store ?? TodoStore();

  /// Relevant notifications that arrived after [since] (all of today's
  /// horizon when null). Its length is the "3 new" on the Update row.
  Future<List<BriefingItem>> candidates(DateTime now, {DateTime? since}) async {
    final prefs = await SharedPreferences.getInstance();
    final aliases = Map<String, String>.from(
      jsonDecode(prefs.getString('vault_category_aliases') ?? '{}'),
    );
    final excluded = await loadExcludedSources();
    await NotificationIngest.whenCaughtUp();
    await EmbeddingBackfill.whenDone().timeout(
      const Duration(seconds: 15),
      onTimeout: () {},
    );
    final entries = await IsarDataSource.getAllEntries();
    final pool = since == null
        ? entries
        : entries.where((e) => e.timestamp.isAfter(since)).toList();
    final isDesktop = Platform.isMacOS || Platform.isWindows;
    return selectForBriefing(
      pool,
      now,
      aliases: aliases,
      blockedCategories: excluded.toList(),
      priorityVector: isDesktop ? null : priorityQueryEmbedding,
      affinity: (await ChatContextStore.loadEngagement()).affinity,
      limit: 25,
    );
  }

  Future<void> make(DateTime now) async {
    if (kEchoDemo) {
      // The filming build writes its scripted list, after a believable pause.
      await Future<void>.delayed(const Duration(milliseconds: 2600));
      return DemoSeed.writeTodoList();
    }
    final picked = await candidates(now);

    List<NewTodo> todos;
    final reply = await _ask(
      makeInstruction,
      numberedLines(picked, now, myTurns: await ChatContextStore.loadMyTurns()),
    );
    if (reply != null) {
      todos = parseMakeReply(reply);
    } else {
      todos = [
        for (final i in localPicks(picked))
          (title: localTitle(picked[i].entry, now), source: i + 1, when: null),
      ];
    }

    // Applied to the list as it is now, not as it was before the model was
    // asked: anything ticked or added while it thought is kept.
    await store.edit(
      (items, meta) => (
        applyMake(
          existing: items,
          candidates: picked,
          todos: todos,
          firstId: freeId(items, meta),
          now: now,
        ),
        meta.copyWith(madeAt: now, updatedAt: now),
      ),
    );
  }

  /// Returns how many items were added or changed.
  Future<int> update(DateTime now) async {
    if (kEchoDemo) return 0;
    final (items, meta) = await store.load();
    final fresh = await candidates(now, since: meta.updatedAt ?? meta.madeAt);
    if (fresh.isEmpty) {
      await store.edit((items, meta) => (items, meta.copyWith(updatedAt: now)));
      return 0;
    }

    final today = startOfDay(now);
    final open = items.where((i) => !i.done && !i.day.isBefore(today)).toList();

    List<NewTodo> add;
    List<TodoChange> change;
    final reply = await _ask(
      updateInstruction,
      'Open items:\n${open.isEmpty ? '(none)' : openItemLines(open, now)}\n\n'
      'New notifications:\n${numberedLines(fresh, now, myTurns: await ChatContextStore.loadMyTurns())}',
    );
    if (reply != null) {
      final parsed = parseUpdateReply(reply);
      add = parsed.add;
      change = parsed.change;
    } else {
      add = [
        for (final i in localPicks(fresh))
          (title: localTitle(fresh[i].entry, now), source: i + 1, when: null),
      ];
      change = const [];
    }

    // Changes name items by id, so they still land on the right item if the
    // list moved on meanwhile (one deleted since is simply skipped).
    var touched = 0;
    await store.edit((items, meta) {
      final next = applyUpdate(
        existing: items,
        candidates: fresh,
        add: add,
        change: change,
        firstId: freeId(items, meta),
        now: now,
      );
      final ids = {for (final i in items) i.id};
      touched =
          next.length -
          items.length +
          change.where((c) => ids.contains(c.id)).length;
      return (next, meta.copyWith(updatedAt: now));
    });
    return touched;
  }

  /// Puts [entries] (chosen in Ask Echo) on the list and returns what was
  /// added: nothing for messages already on it or with nothing to do.
  Future<List<TodoItem>> addFrom(List<RawData> entries, DateTime now) async {
    final candidates = [
      for (final e in entries)
        BriefingItem(
          e,
          relevanceWindows('${e.sender} ${e.content}', e.timestamp).first,
        ),
    ];
    final reply = await _ask(
      makeInstruction,
      numberedLines(
        candidates,
        now,
        myTurns: await ChatContextStore.loadMyTurns(),
      ),
    );
    final todos = reply != null
        ? parseMakeReply(reply)
        : [
            for (var i = 0; i < candidates.length; i++)
              (
                title: localTitle(candidates[i].entry, now),
                source: i + 1,
                when: null,
              ),
          ];
    var added = const <TodoItem>[];
    await store.edit((items, meta) {
      final next = applyMake(
        existing: items,
        candidates: candidates,
        todos: todos,
        firstId: freeId(items, meta),
        now: now,
      );
      added = next.sublist(items.length);
      return added.isEmpty ? null : (next, meta);
    });
    TodoStore.changed.value++;
    return added;
  }

  /// How long the model gets before titles are built locally instead.
  static const askTimeout = Duration(seconds: 45);

  /// Gemini's reply, or null when the cloud engine isn't in use, the call
  /// fails or it takes longer than [askTimeout] — the caller then builds
  /// titles locally.
  Future<String?> _ask(String instruction, String prompt) =>
      askGeminiJson(instruction, prompt, label: 'TODO').timeout(
        askTimeout,
        onTimeout: () {
          debugPrint('TODO: no reply in ${askTimeout.inSeconds}s, going local');
          return null;
        },
      );
}
