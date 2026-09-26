import 'dart:convert';

import 'package:project_echo/features/todo/data/todo_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the to-do list in shared preferences. The native widgets read and
/// write the same keys (`flutter.todo_items_v1`), so every read reloads from
/// disk first to pick up items ticked off on the home screen.
class TodoStore {
  static const itemsKey = 'todo_items_v1';
  static const metaKey = 'todo_meta_v1';

  Future<(List<TodoItem>, TodoMeta)> load() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final items = <TodoItem>[];
    try {
      final raw = prefs.getString(itemsKey);
      if (raw != null) {
        for (final j in jsonDecode(raw) as List) {
          items.add(TodoItem.fromJson(j as Map<String, dynamic>));
        }
      }
    } catch (_) {
      // Unreadable list: show nothing rather than crash. It is not
      // overwritten until the next save.
    }
    var meta = const TodoMeta();
    try {
      final raw = prefs.getString(metaKey);
      if (raw != null) {
        meta = TodoMeta.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {}
    return (items, meta);
  }

  Future<void> save(List<TodoItem> items, TodoMeta meta) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      itemsKey,
      jsonEncode(items.map((i) => i.toJson()).toList()),
    );
    await prefs.setString(metaKey, jsonEncode(meta.toJson()));
  }
}
