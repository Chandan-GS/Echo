import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/features/todo/data/todo_item.dart';
import 'package:project_echo/features/todo/data/todo_store.dart';
import 'package:project_echo/features/todo/presentation/widgets/reminder_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

final created = DateTime(2026, 10, 3, 9);

TodoItem todo(int id, {bool done = false, String? key}) => TodoItem(
  id: id,
  title: 'Item $id',
  day: DateTime(2026, 10, 3),
  time: null,
  sort: TodoItem.noTimeSort,
  sender: 'Rahul',
  app: 'Whatsapp',
  sourceText: '',
  sourceKey: key ?? 'Rahul|$id',
  created: created,
  done: done,
);

String encode(List<TodoItem> items) =>
    jsonEncode(items.map((i) => i.toJson()).toList());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TodoStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = TodoStore();
  });

  test('edits made at once all land, each with its own id', () async {
    await store.save([todo(1)], const TodoMeta(nextId: 2));
    TodoEdit add(String key) =>
        (items, meta) =>
            ([...items, todo(freeId(items, meta), key: key)], meta);

    await Future.wait([
      store.edit(add('a')),
      store.edit(add('b')),
      store.edit(add('c')),
    ]);

    final (items, meta) = await store.load();
    expect(items.map((i) => i.sourceKey), ['Rahul|1', 'a', 'b', 'c']);
    expect(items.map((i) => i.id).toSet(), hasLength(4));
    expect(meta.nextId, 5);
  });

  test('an edit applies to the list as stored, not an earlier copy', () async {
    await store.save([todo(1), todo(2)], const TodoMeta(nextId: 3));
    final (before, _) = await store.load();
    expect(before.every((i) => !i.done), isTrue);

    // A home-screen widget ticks item 1 natively (TodoWidgetData.setDone).
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      TodoStore.itemsKey,
      encode([todo(1, done: true), todo(2)]),
    );

    await store.edit(
      (items, meta) => (
        [for (final i in items) i.id == 2 ? i.withDone(true, created) : i],
        meta,
      ),
    );
    final (after, _) = await store.load();
    expect(after.every((i) => i.done), isTrue);
  });

  test('the next id never repeats one already on the list', () async {
    // Something else (a paired computer, an older build) added id 7 without
    // moving the counter on.
    await store.save([todo(1), todo(7)], const TodoMeta(nextId: 2));
    final (items, meta) = await store.load();
    expect(freeId(items, meta), 8);
    final saved = await store.edit((items, meta) => (items, meta));
    expect(saved!.$2.nextId, 8);
  });

  test('an unreadable list is never saved over', () async {
    const broken = '[{"id": 1, "title": "Half a list"';
    SharedPreferences.setMockInitialValues({
      'flutter.${TodoStore.itemsKey}': broken,
    });
    final (items, _) = await store.load();
    expect(items, isEmpty);

    final saved = await store.edit(
      (items, meta) => ([...items, todo(1)], meta),
    );
    expect(saved, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(TodoStore.itemsKey), broken);
  });

  test('a throwing edit does not stall the ones after it', () async {
    final failing = store.edit((_, _) => throw StateError('boom'));
    await expectLater(failing, throwsStateError);
    final saved = await store.edit((items, meta) => ([todo(1)], meta));
    expect(saved!.$1, hasLength(1));
  });

  test('the reminder wheel keeps an odd minute instead of rounding it', () {
    expect(minuteStops(37), [0, 5, 10, 15, 20, 25, 30, 35, 37, 40, 45, 50, 55]);
    expect(minuteStops(40), hasLength(12));
  });
}
