import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:project_echo/core/services/gemini_service.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/datasources/priority_query_embedding.dart';
import 'package:project_echo/features/echo/data/relevance/briefing_selection.dart';
import 'package:project_echo/features/echo/data/relevance/temporal_relevance.dart';
import 'package:project_echo/features/todo/data/todo_planner.dart';
import 'package:project_echo/features/todo/data/todo_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    final blocked = prefs.getStringList('vault_blocked_categories') ?? [];
    final entries = await IsarDataSource.getAllEntries();
    final pool = since == null
        ? entries
        : entries.where((e) => e.timestamp.isAfter(since)).toList();
    final isDesktop = Platform.isMacOS || Platform.isWindows;
    return selectForBriefing(
      pool,
      now,
      aliases: aliases,
      blockedCategories: blocked,
      priorityVector: isDesktop ? null : priorityQueryEmbedding,
      limit: 25,
    );
  }

  Future<void> make(DateTime now) async {
    final (items, meta) = await store.load();
    final picked = await candidates(now);

    List<NewTodo> todos;
    final reply = await _ask(makeInstruction, numberedLines(picked, now));
    if (reply != null) {
      todos = parseMakeReply(reply);
    } else {
      todos = [
        for (var i = 0; i < picked.length; i++)
          (title: localTitle(picked[i].entry, now), source: i + 1),
      ];
    }

    final next = applyMake(
      existing: items,
      candidates: picked,
      todos: todos,
      firstId: meta.nextId,
      now: now,
    );
    await store.save(
      next,
      meta.copyWith(
        madeAt: now,
        updatedAt: now,
        nextId: meta.nextId + (next.length - items.length),
      ),
    );
  }

  /// Returns how many items were added or changed.
  Future<int> update(DateTime now) async {
    final (items, meta) = await store.load();
    final fresh = await candidates(now, since: meta.updatedAt ?? meta.madeAt);
    if (fresh.isEmpty) {
      await store.save(items, meta.copyWith(updatedAt: now));
      return 0;
    }

    final today = startOfDay(now);
    final open = items.where((i) => !i.done && !i.day.isBefore(today)).toList();

    List<NewTodo> add;
    List<TodoChange> change;
    final reply = await _ask(
      updateInstruction,
      'Open items:\n${open.isEmpty ? '(none)' : openItemLines(open, now)}\n\n'
      'New notifications:\n${numberedLines(fresh, now)}',
    );
    if (reply != null) {
      final parsed = parseUpdateReply(reply);
      add = parsed.add;
      change = parsed.change;
    } else {
      add = [
        for (var i = 0; i < fresh.length; i++)
          (title: localTitle(fresh[i].entry, now), source: i + 1),
      ];
      change = const [];
    }

    final next = applyUpdate(
      existing: items,
      candidates: fresh,
      add: add,
      change: change,
      firstId: meta.nextId,
      now: now,
    );
    final added = next.length - items.length;
    await store.save(
      next,
      meta.copyWith(updatedAt: now, nextId: meta.nextId + added),
    );
    return added + change.length;
  }

  /// Gemini's reply, or null when the cloud engine isn't in use or the call
  /// fails — the caller then builds titles locally.
  Future<String?> _ask(String instruction, String prompt) async {
    final prefs = await SharedPreferences.getInstance();
    final offline = prefs.getBool('is_offline_engine') ?? true;
    final key = prefs.getString('gemini_api_key') ?? '';
    if (offline || key.isEmpty) return null;
    try {
      debugPrint('=== TODO PROMPT ===\n$prompt\n==================');
      final reply = await GeminiService.instance.generateJson(
        key,
        prompt,
        systemInstruction: instruction,
      );
      debugPrint('=== TODO REPLY ===\n$reply\n==================');
      return reply;
    } catch (e) {
      debugPrint('To-do generation fell back to local titles: $e');
      return null;
    }
  }
}
