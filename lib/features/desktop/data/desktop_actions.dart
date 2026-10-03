import 'dart:convert';

import 'package:project_echo/core/services/echo_server_service.dart';
import 'package:project_echo/core/services/phone_actions.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/reply/reply_sender.dart';
import 'package:project_echo/features/todo/data/todo_item.dart';
import 'package:project_echo/features/todo/data/todo_planner.dart';
import 'package:project_echo/features/todo/data/todo_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Everything the computer does to the owner's chats, list and reminders,
/// done through the phone (see PhoneActions). The computer's copy updates
/// at once; the phone does the real thing within about 20 seconds.
///
/// Desktop screens use these, never Reminders.set, TodoCubit.toggle or
/// ReplySender.send directly: those would change only the computer's copy.
class DesktopActions {
  DesktopActions._();

  /// Replies to [to] (its chat) with [text]. Returns the action's id, to
  /// follow with [state].
  static Future<String> reply(RawData to, String text) => PhoneActions.send({
    'kind': 'reply',
    'thread': to.thread,
    'text': text,
    'to': to.isGroup && (to.threadTitle?.isNotEmpty ?? false)
        ? to.threadTitle
        : to.sender,
  });

  /// Asks the phone to open [entry]'s chat: it shows a notification that
  /// opens it when tapped.
  static Future<String> openChat(RawData entry) => PhoneActions.send({
    'kind': 'open_chat',
    'thread': entry.thread,
    'to': entry.isGroup && (entry.threadTitle?.isNotEmpty ?? false)
        ? entry.threadTitle
        : entry.sender,
  });

  /// How a reply to [entry]'s chat would go on the phone right now, as the
  /// phone last said: [ReplyRoute.send] goes out at once; the others wait
  /// for a tap on the phone.
  static Future<ReplyRoute> routeFor(RawData entry) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final routes =
          jsonDecode(prefs.getString(EchoServerService.replyRoutesKey) ?? '{}')
              as Map;
      return ReplyRoute.values.asNameMap()[routes[entry.thread]] ??
          ReplyRoute.pick;
    } catch (_) {
      return ReplyRoute.pick;
    }
  }

  static Future<String> tick(TodoItem item, {required bool done}) =>
      PhoneActions.send({'kind': 'todo_done', 'id': item.id, 'done': done});

  static Future<String> move(TodoItem item, DateTime day) => PhoneActions.send({
    'kind': 'todo_move',
    'id': item.id,
    'day': dayKey(day),
  });

  static Future<String> delete(TodoItem item) =>
      PhoneActions.send({'kind': 'todo_delete', 'id': item.id});

  /// Puts back [item] after [delete], for Undo.
  static Future<String> restore(TodoItem item) =>
      PhoneActions.send({'kind': 'todo_add', 'item': item.toJson()});

  /// An id no item has yet: the computer's copy already holds adds the
  /// phone hasn't done, so two quick adds don't share one. The phone gives
  /// a new id if its own list has taken it meanwhile.
  static Future<int> _nextId() async {
    final (items, meta) = await TodoStore().load();
    final top = items.fold(0, (m, i) => i.id > m ? i.id : m);
    return meta.nextId > top ? meta.nextId : top + 1;
  }

  /// Adds what the owner typed ("call the plumber at 11 tomorrow"); returns
  /// the item as it'll appear.
  static Future<TodoItem> add(String text) async {
    final item = typedItem(text, await _nextId(), DateTime.now());
    await PhoneActions.send({'kind': 'todo_add', 'item': item.toJson()});
    return item;
  }

  /// Puts [entry] on the list as written (the phone's own planner names it
  /// properly on its next update).
  static Future<TodoItem> addMessage(RawData entry) async {
    final now = DateTime.now();
    final item = typedItem(entry.content, await _nextId(), now);
    final fromMessage = TodoItem(
      id: item.id,
      title: item.title,
      day: item.day,
      time: item.time,
      sort: item.sort,
      sender: entry.who,
      app: entry.source,
      sourceText: entry.content,
      sourceKey: sourceKeyOf(entry),
      created: now,
    );
    await PhoneActions.send({'kind': 'todo_add', 'item': fromMessage.toJson()});
    return fromMessage;
  }

  /// A reminder about [key] (a to-do's or message's source key) at [at].
  static Future<String> remind({
    required String key,
    required DateTime at,
    required String title,
    required String body,
    int? todoId,
    String? thread,
  }) => PhoneActions.send({
    'kind': 'remind',
    'key': key,
    'at': at.millisecondsSinceEpoch,
    'title': title,
    'body': body,
    'todoId': todoId,
    'thread': thread,
  });

  static Future<String> unremind(String key) =>
      PhoneActions.send({'kind': 'unremind', 'key': key});

  /// How the action with [id] is going, or null once it's forgotten.
  static Future<PhoneAction?> state(String id) async =>
      (await PhoneActions.all()).where((a) => a.id == id).firstOrNull;
}
