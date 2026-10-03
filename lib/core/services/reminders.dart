import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/relevance/temporal_relevance.dart';
import 'package:project_echo/features/todo/data/todo_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "Remind me at 7:40": a notification about a message or a to-do, at that
/// time or within ten minutes after (see Reminders.kt). One per message, keyed
/// by its source key, so a reminder set on Home, in Ask Echo or on the to-do
/// made from it is the same reminder.
class Reminders {
  Reminders._();

  /// Ticks whenever a reminder is set or cancelled, so every screen showing
  /// one stays in step.
  static final changed = ValueNotifier<int>(0);

  static const _channel = MethodChannel('project_echo/reminders');
  static const _key = 'echo_reminders_v1';

  /// Notification ids from here up, clear of Echo's other notifications.
  static const _firstId = 100000;

  /// When the reminder about [message] goes off, if one is set and still to
  /// come.
  static Future<DateTime?> setFor(String message) async {
    final r = (await _load())[message];
    if (r == null) return null;
    final at = DateTime.fromMillisecondsSinceEpoch(r['at'] as int);
    return at.isAfter(DateTime.now()) ? at : null;
  }

  /// Every reminder still to come, by message.
  static Future<Map<String, DateTime>> all() async {
    final now = DateTime.now();
    return {
      for (final MapEntry(:key, :value) in (await _load()).entries)
        if (DateTime.fromMillisecondsSinceEpoch(
          value['at'] as int,
        ).isAfter(now))
          key: DateTime.fromMillisecondsSinceEpoch(value['at'] as int),
    };
  }

  /// [todoId] lets the notification's Done tick the to-do off; [thread] lets
  /// its Open chat open the chat the message came from.
  static Future<void> set({
    required String message,
    required DateTime at,
    required String title,
    required String body,
    int? todoId,
    String? thread,
  }) async {
    final all = await _load()
      ..removeWhere(
        (_, r) => DateTime.fromMillisecondsSinceEpoch(
          r['at'] as int,
        ).isBefore(DateTime.now()),
      );
    final used = {for (final r in all.values) r['id'] as int};
    var id = _firstId;
    while (used.contains(id)) {
      id++;
    }
    // Setting it again (a new time) keeps its notification id.
    id = (all[message]?['id'] as int?) ?? id;
    // Everything the notification needs, so the phone can set it again
    // after a restart or an update (see Reminders.kt).
    all[message] = {
      'id': id,
      'at': at.millisecondsSinceEpoch,
      'title': title,
      'body': body,
      'todoId': ?todoId,
      'thread': ?thread,
    };
    await _save(all);
    await _call('set', {
      'id': id,
      'key': message,
      'at': at.millisecondsSinceEpoch,
      'title': title,
      'body': body,
      'todoId': todoId,
      'thread': thread,
    });
    changed.value++;
  }

  static Future<void> cancel(String message) async {
    final all = await _load();
    final r = all.remove(message);
    await _save(all);
    if (r != null) await _call('cancel', {'id': r['id']});
    changed.value++;
  }

  static Future<void> _call(String method, Map<String, Object?> args) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // desktop builds
    }
  }

  static Future<Map<String, Map<String, dynamic>>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    // A snooze from the notification rewrites this natively.
    await prefs.reload();
    try {
      final raw = jsonDecode(prefs.getString(_key) ?? '{}') as Map;
      return {
        for (final e in raw.entries)
          e.key as String: Map<String, dynamic>.from(e.value as Map),
      };
    } catch (_) {
      return {};
    }
  }

  static Future<void> _save(Map<String, Map<String, dynamic>> all) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(all));
  }
}

/// When to remind about [e]: 20 minutes before the time it names, so the
/// reminder (which can take up to ten minutes) still comes before it. Null
/// when it names no time, or there isn't time to remind.
DateTime? reminderTimeFor(RawData e, DateTime now) {
  final w = relevanceWindows('${e.sender} ${e.content}', e.timestamp).first;
  if (!w.explicit || !w.hasTime) return null;
  final at = w.start.subtract(reminderLead);
  return at.isAfter(now.add(const Duration(minutes: 5))) ? at : null;
}

/// How long before a to-do's time Echo suggests reminding.
const reminderLead = Duration(minutes: 20);

/// Echo's suggested reminder for [item]: [reminderLead] before its time, if
/// that's still more than five minutes away. Null when it names no time.
DateTime? suggestedReminder(TodoItem item, DateTime now) {
  final start = item.startsAt;
  if (item.done || start == null) return null;
  final at = start.subtract(reminderLead);
  return at.isAfter(now.add(const Duration(minutes: 5))) ? at : null;
}
