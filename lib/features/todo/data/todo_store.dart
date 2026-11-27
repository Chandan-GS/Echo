import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:project_echo/features/todo/data/todo_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A change to the list: given what's stored now, the list and bookkeeping
/// to save, or null to leave it as it is.
typedef TodoEdit =
    (List<TodoItem>, TodoMeta)? Function(List<TodoItem> items, TodoMeta meta);

/// Persists the to-do list in shared preferences. The native widgets read and
/// write the same keys (`flutter.todo_items_v1`), so every read reloads from
/// disk first to pick up items ticked off on the home screen.
///
/// Changes go through [edit], one at a time across every TodoStore in the
/// app, each applied to the list as it is on disk at that moment. So making
/// the list (which waits seconds on the model) can't overwrite a tick, a
/// typed add or an Ask Echo add that landed meanwhile, and two adds never
/// take the same id.
class TodoStore {
  static const itemsKey = 'todo_items_v1';
  static const metaKey = 'todo_meta_v1';

  /// Ticks when something other than the to-do card changes the list (Ask
  /// Echo adding or undoing items), so the card can re-read it.
  static final changed = ValueNotifier<int>(0);

  /// The end of the last queued write; the next one starts after it.
  static Future<void> _writes = Future.value();

  Future<(List<TodoItem>, TodoMeta)> load() async {
    final read = await _read();
    return (read.items, read.meta);
  }

  /// Applies [change] to the list as stored now and saves the result, after
  /// any write already under way. Returns what was saved, or null when
  /// [change] left the list alone or the stored list couldn't be read — an
  /// unreadable list is never overwritten, so nothing on it is lost to a
  /// save made from an empty copy.
  Future<(List<TodoItem>, TodoMeta)?> edit(TodoEdit change) =>
      _serialized(() async {
        final read = await _read();
        if (!read.readable) {
          debugPrint('To-do list unreadable; not saving over it.');
          return null;
        }
        final result = change(read.items, read.meta);
        if (result == null) return null;
        final (items, meta) = result;
        // Whatever the change counted, the next id is one nobody has.
        final next = meta.copyWith(nextId: freeId(items, meta));
        await _write(items, next);
        return (items, next);
      });

  /// Replaces the whole list (the demo build's scripted one). Everything
  /// else should [edit].
  Future<void> save(List<TodoItem> items, TodoMeta meta) =>
      _serialized(() => _write(items, meta));

  /// Removes the items with [ids] (undoing an add).
  Future<void> remove(Set<int> ids) async {
    await edit(
      (items, meta) => (items.where((i) => !ids.contains(i.id)).toList(), meta),
    );
    changed.value++;
  }

  static Future<T> _serialized<T>(Future<T> Function() write) {
    final done = Completer<void>();
    final run = _writes.then((_) => write());
    _writes = done.future;
    // The queue moves on whether this write worked or not.
    run.then((_) => done.complete(), onError: (_) => done.complete());
    return run;
  }

  Future<({List<TodoItem> items, TodoMeta meta, bool readable})> _read() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final items = <TodoItem>[];
    var readable = true;
    try {
      final raw = prefs.getString(itemsKey);
      if (raw != null) {
        for (final j in jsonDecode(raw) as List) {
          items.add(TodoItem.fromJson(j as Map<String, dynamic>));
        }
      }
    } catch (_) {
      // Unreadable list: show nothing rather than crash, and don't save
      // over it (see [edit]).
      items.clear();
      readable = false;
    }
    var meta = const TodoMeta();
    try {
      final raw = prefs.getString(metaKey);
      if (raw != null) {
        meta = TodoMeta.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {}
    return (items: items, meta: meta, readable: readable);
  }

  Future<void> _write(List<TodoItem> items, TodoMeta meta) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      itemsKey,
      jsonEncode(items.map((i) => i.toJson()).toList()),
    );
    await prefs.setString(metaKey, jsonEncode(meta.toJson()));
  }
}
