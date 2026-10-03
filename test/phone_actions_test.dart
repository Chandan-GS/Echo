import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/core/services/phone_actions.dart';
import 'package:project_echo/core/services/reminders.dart';
import 'package:project_echo/features/todo/data/todo_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object> todo(int id, {bool done = false}) => {
  'id': id,
  'title': 'Item $id',
  'day': '2026-10-03',
  'sort': 0,
  'done': done,
  'key': 'k$id',
};

Future<List<Map<String, dynamic>>> items() async {
  final prefs = await SharedPreferences.getInstance();
  return [
    for (final j in jsonDecode(prefs.getString(TodoStore.itemsKey)!) as List)
      Map<String, dynamic>.from(j as Map),
  ];
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'flutter.${TodoStore.itemsKey}': jsonEncode([todo(1), todo(2)]),
    });
  });

  test('a change shows at once, and survives a snapshot until done', () async {
    await PhoneActions.send({'kind': 'todo_done', 'id': 1, 'done': true});
    expect((await items()).first['done'], isTrue);

    // A snapshot from before the phone did it puts the old list back…
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(TodoStore.itemsKey, jsonEncode([todo(1), todo(2)]));
    await PhoneActions.applyToMirror();
    // …and the change is applied again.
    expect((await items()).first['done'], isTrue);
  });

  test('the phone collects, then reports', () async {
    final id = await PhoneActions.send({
      'kind': 'reply',
      'thread': 'com.whatsapp:aa',
      'text': 'On my way',
    });
    final open = await PhoneActions.forPhone();
    expect(open.single.id, id);
    expect((await PhoneActions.all()).single.state, ActionState.collected);

    // Offered again until reported, in case the report was lost.
    expect((await PhoneActions.forPhone()).single.id, id);

    await PhoneActions.report([
      {'id': id, 'ok': true, 'outcome': 'sent'},
    ]);
    final done = (await PhoneActions.all()).single;
    expect(done.state, ActionState.done);
    expect(done.outcome, 'sent');
    expect(await PhoneActions.forPhone(), isEmpty);
  });

  test('moves, deletes, adds and reminders apply to the mirror', () async {
    await PhoneActions.send({
      'kind': 'todo_move',
      'id': 2,
      'day': '2026-10-04',
    });
    await PhoneActions.send({'kind': 'todo_delete', 'id': 1});
    await PhoneActions.send({'kind': 'todo_add', 'item': todo(9)});
    await PhoneActions.send({
      'kind': 'remind',
      'key': 'k2',
      'at': 1791036600000,
      'title': 'Item 2',
      'body': '',
    });
    final list = await items();
    expect(list.map((i) => i['id']), [2, 9]);
    expect(list.first['day'], '2026-10-04');
    final prefs = await SharedPreferences.getInstance();
    final reminders = jsonDecode(prefs.getString(Reminders.storeKey)!) as Map;
    expect(reminders['k2']['at'], 1791036600000);
  });
}
