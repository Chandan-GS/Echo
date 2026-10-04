import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:project_echo/core/services/reminders.dart';
import 'package:project_echo/demo/demo_mode.dart';
import 'package:project_echo/features/todo/data/todo_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What happened to something sent to the phone.
enum ActionState {
  /// Waiting for the phone to collect it.
  waiting,

  /// The phone has it.
  collected,

  /// Done on the phone.
  done,

  /// The phone couldn't do it.
  failed,
}

/// One thing done on the computer that the phone carries out.
class PhoneAction {
  final String id;
  final Map<String, dynamic> body;
  final ActionState state;

  /// The phone's word on how it went: "sent", "ready" (a notification on
  /// the phone, tap to send), "done", or why it failed.
  final String? outcome;
  final DateTime at;

  const PhoneAction({
    required this.id,
    required this.body,
    required this.state,
    required this.at,
    this.outcome,
  });

  String get kind => body['kind'] as String? ?? '';

  Map<String, dynamic> toJson() => {
    'id': id,
    'body': body,
    'state': state.name,
    'outcome': outcome,
    'at': at.millisecondsSinceEpoch,
  };

  static PhoneAction? fromJson(Object? j) {
    if (j is! Map) return null;
    final body = j['body'];
    if (body is! Map) return null;
    return PhoneAction(
      id: j['id'] as String? ?? '',
      body: Map<String, dynamic>.from(body),
      state: ActionState.values.asNameMap()[j['state']] ?? ActionState.waiting,
      outcome: j['outcome'] as String?,
      at: DateTime.fromMillisecondsSinceEpoch((j['at'] as int?) ?? 0),
    );
  }

  PhoneAction copyWith({ActionState? state, String? outcome}) => PhoneAction(
    id: id,
    body: body,
    state: state ?? this.state,
    outcome: outcome ?? this.outcome,
    at: at,
  );
}

/// The computer's half of doing things through the phone: replies, to-do
/// changes and reminders made here are queued; the phone collects them
/// (`GET /actions`) and reports back (`POST /actions/done`), see
/// DesktopRelay.kt. Until then the computer shows them as done, applying
/// them again over every snapshot the phone sends.
class PhoneActions {
  PhoneActions._();

  static const _key = 'desktop_phone_actions_v1';

  /// Finished actions are kept this long, for the screens that show them.
  static const _keep = Duration(hours: 24);

  /// Ticks when an action is added, collected or finished.
  static final changed = ValueNotifier<int>(0);

  static Future<List<PhoneAction>> all() async {
    final prefs = await SharedPreferences.getInstance();
    return _decode(prefs.getString(_key));
  }

  /// Queues [body] (`{"kind": "reply", …}`) for the phone; returns its id.
  static Future<String> send(Map<String, dynamic> body) async {
    final now = DateTime.now();
    final action = PhoneAction(
      id: 'a${now.microsecondsSinceEpoch}',
      body: body,
      state: ActionState.waiting,
      at: now,
    );
    await _update((list) => [...list, action]);
    // Shown at once, before the phone has it.
    await applyToMirror();
    // The filming build has no phone: it "does" everything a moment later.
    if (kEchoDemo) {
      Future<void>.delayed(const Duration(milliseconds: 1200), () {
        report([
          {'id': action.id, 'ok': true, 'outcome': body['kind'] == 'reply' ? 'sent' : 'done'},
        ]);
      });
    }
    return action.id;
  }

  /// What the phone hasn't done yet, for `GET /actions`. Collected ones are
  /// offered again too: the phone skips any it already did, so one that was
  /// done but whose report got lost isn't stuck.
  static Future<List<PhoneAction>> forPhone() async {
    final open = <PhoneAction>[];
    await _update(
      (list) => [
        for (final a in list)
          if (a.state == ActionState.waiting ||
              a.state == ActionState.collected) ...[
            a.copyWith(state: ActionState.collected),
          ] else
            a,
      ],
      then: (list) =>
          open.addAll(list.where((a) => a.state == ActionState.collected)),
    );
    return open;
  }

  /// The phone's report: `[{"id": …, "ok": true, "outcome": "sent"}]`.
  static Future<void> report(List<Object?> results) async {
    final byId = {
      for (final r in results.whereType<Map>())
        if (r['id'] is String) r['id'] as String: r,
    };
    await _update(
      (list) => [
        for (final a in list)
          if (byId[a.id] case final r?)
            a.copyWith(
              state: r['ok'] == false ? ActionState.failed : ActionState.done,
              outcome: r['outcome']?.toString(),
            )
          else
            a,
      ],
    );
  }

  /// Applies what the phone hasn't confirmed yet to the computer's copy of
  /// the list and the reminders, so a snapshot sent before the phone did
  /// them doesn't undo them on screen.
  static Future<void> applyToMirror() async {
    final prefs = await SharedPreferences.getInstance();
    final open = _decode(prefs.getString(_key)).where(
      (a) => a.state != ActionState.done && a.state != ActionState.failed,
    );
    if (open.isEmpty) return;
    var items = _list(prefs.getString(TodoStore.itemsKey));
    final reminders = _map(prefs.getString(Reminders.storeKey));
    for (final a in open) {
      final b = a.body;
      switch (a.kind) {
        case 'todo_done':
          items = [
            for (final i in items)
              i['id'] == b['id']
                  ? {
                      ...i,
                      'done': b['done'] == true,
                      'doneAt': b['done'] == true
                          ? a.at.millisecondsSinceEpoch
                          : null,
                    }
                  : i,
          ];
        case 'todo_move':
          items = [
            for (final i in items)
              i['id'] == b['id'] ? {...i, 'day': b['day']} : i,
          ];
        case 'todo_delete':
          items = [
            for (final i in items)
              if (i['id'] != b['id']) i,
          ];
        case 'todo_add':
          final item = b['item'];
          if (item is Map && !items.any((i) => i['key'] == item['key'])) {
            items = [...items, Map<String, dynamic>.from(item)];
          }
        case 'remind':
          reminders[b['key'] as String] = {
            'id': 0,
            'at': b['at'],
            'title': b['title'],
            'body': b['body'],
          };
        case 'unremind':
          reminders.remove(b['key']);
      }
    }
    await prefs.setString(TodoStore.itemsKey, jsonEncode(items));
    await prefs.setString(Reminders.storeKey, jsonEncode(reminders));
    TodoStore.changed.value++;
    Reminders.changed.value++;
  }

  static Future<void> _update(
    List<PhoneAction> Function(List<PhoneAction>) change, {
    void Function(List<PhoneAction>)? then,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final next = change(_decode(prefs.getString(_key)))
      ..removeWhere(
        (a) =>
            (a.state == ActionState.done || a.state == ActionState.failed) &&
            now.difference(a.at) > _keep,
      );
    await prefs.setString(_key, jsonEncode([for (final a in next) a.toJson()]));
    then?.call(next);
    changed.value++;
  }

  static List<PhoneAction> _decode(String? raw) {
    try {
      return [
        for (final j in jsonDecode(raw ?? '[]') as List)
          ?PhoneAction.fromJson(j),
      ];
    } catch (_) {
      return [];
    }
  }

  static List<Map<String, dynamic>> _list(String? raw) {
    try {
      return [
        for (final j in jsonDecode(raw ?? '[]') as List)
          if (j is Map) Map<String, dynamic>.from(j),
      ];
    } catch (_) {
      return [];
    }
  }

  static Map<String, dynamic> _map(String? raw) {
    try {
      return Map<String, dynamic>.from(jsonDecode(raw ?? '{}') as Map);
    } catch (_) {
      return {};
    }
  }
}
