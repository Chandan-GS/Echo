import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/core/services/analytics_service.dart';
import 'package:project_echo/core/services/reminders.dart';
import 'package:project_echo/features/echo/data/relevance/briefing_selection.dart';
import 'package:project_echo/features/todo/data/todo_generator.dart';
import 'package:project_echo/features/todo/data/todo_item.dart';
import 'package:project_echo/features/todo/data/todo_store.dart';
import 'package:project_echo/features/todo/presentation/cubit/todo_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sat 3 Oct 2026, 4:12 PM, unless a test moves it.
var clockNow = DateTime(2026, 10, 3, 16, 12);
DateTime clock() => clockNow;

TodoItem todo(int id, {bool done = false, int dayOffset = 0}) => TodoItem(
  id: id,
  title: 'Item $id',
  day: DateTime(2026, 10, 3 + dayOffset),
  time: '8 PM',
  sort: 20 * 60,
  sender: 'Rahul',
  app: 'Whatsapp',
  sourceText: 'At 8?',
  sourceKey: 'Rahul|$id',
  created: DateTime(2026, 10, 3, 9),
  done: done,
);

/// Makes the list only when told to, so a test can change the list while
/// "the model" is thinking. What it adds is merged the way the real
/// generator does it.
class _SlowGenerator extends TodoGenerator {
  final Completer<void> reply = Completer();
  _SlowGenerator(TodoStore store) : super(store: store);

  @override
  Future<List<BriefingItem>> candidates(
    DateTime now, {
    DateTime? since,
  }) async => const [];

  @override
  Future<void> make(DateTime now) async {
    await reply.future;
    await store.edit(
      (items, meta) => (
        [
          ...items,
          todo(freeId(items, meta)).copyWith(title: 'From the briefing'),
        ],
        meta.copyWith(madeAt: now, updatedAt: now),
      ),
    );
  }
}

Future<List<TodoItem>> stored() async => (await TodoStore().load()).$1;

/// What TodoWidgetData.setDone / a reminder's Done does natively.
Future<void> tickNatively(int id) async {
  final prefs = await SharedPreferences.getInstance();
  final list = jsonDecode(prefs.getString(TodoStore.itemsKey)!) as List;
  for (final o in list.cast<Map<String, dynamic>>()) {
    if (o['id'] == id) o['done'] = true;
  }
  await prefs.setString(TodoStore.itemsKey, jsonEncode(list));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TodoStore store;
  late _SlowGenerator generator;
  late TodoCubit cubit;

  Future<TodoCubit> start(List<TodoItem> items, {Duration? timeout}) async {
    SharedPreferences.setMockInitialValues({
      'flutter.${TodoStore.itemsKey}': jsonEncode(
        items.map((i) => i.toJson()).toList(),
      ),
      'flutter.${TodoStore.metaKey}': jsonEncode(
        TodoMeta(madeAt: clockNow, nextId: items.length + 1).toJson(),
      ),
    });
    // Analytics isn't set up in tests.
    await Analytics.setEnabled(false);
    store = TodoStore();
    generator = _SlowGenerator(store);
    cubit = TodoCubit(
      store: store,
      generator: generator,
      clock: clock,
      generationTimeout: timeout ?? const Duration(seconds: 90),
    );
    await cubit.load();
    return cubit;
  }

  setUp(() => clockNow = DateTime(2026, 10, 3, 16, 12));
  tearDown(() => cubit.close());

  test('making the list keeps what was ticked and added meanwhile', () async {
    await start([todo(1), todo(2)]);
    final making = cubit.make();
    await cubit.toggle(1);
    final typed = await cubit.addTyped('call the plumber at 11 tomorrow');
    await tickNatively(2); // a home-screen widget
    generator.reply.complete();
    await making;

    final items = await stored();
    expect(items.firstWhere((i) => i.id == 1).done, isTrue);
    expect(items.firstWhere((i) => i.id == 2).done, isTrue);
    expect(items.map((i) => i.title), contains(typed!.title));
    expect(items.map((i) => i.title), contains('From the briefing'));
    expect(items.map((i) => i.id).toSet(), hasLength(items.length));
    expect(cubit.state.items, hasLength(items.length));
  });

  test('ticking one item never undoes a Done made elsewhere', () async {
    await start([todo(1), todo(2)]);
    // The reminder's Done ticks item 1; the app hasn't re-read the list.
    await tickNatively(1);
    expect(cubit.state.items.first.done, isFalse);

    await cubit.toggle(2);
    final items = await stored();
    expect(items.every((i) => i.done), isTrue);
  });

  test('ticking what is already done there leaves it done', () async {
    await start([todo(1)]);
    await tickNatively(1);
    // The owner taps the (stale, unticked) box meaning "done".
    final finished = await cubit.toggle(1);
    expect((await stored()).single.done, isTrue);
    expect(cubit.state.items.single.done, isTrue);
    expect(finished, isFalse);
  });

  test('a tick on Tomorrow can be taken back', () async {
    await start([todo(1, dayOffset: 1)]);
    await cubit.toggle(1);
    expect((await stored()).single.done, isTrue);
    await cubit.setDone(1, false);
    expect((await stored()).single.done, isFalse);
  });

  test('undoing a delete brings its reminder back', () async {
    await start([todo(1)]);
    final at = DateTime(2030, 1, 1, 19, 40);
    await Reminders.set(
      message: 'Rahul|1',
      at: at,
      title: 'Item 1',
      body: 'Rahul: “At 8?”',
      todoId: 1,
      thread: 'whatsapp|rahul',
    );

    final gone = await cubit.remove(1);
    expect(await stored(), isEmpty);
    expect(await Reminders.setFor('Rahul|1'), isNull);

    await cubit.restore(gone!);
    expect((await stored()).single.id, 1);
    expect(await Reminders.setFor('Rahul|1'), at);
    final prefs = await SharedPreferences.getInstance();
    final r =
        (jsonDecode(prefs.getString(Reminders.storeKey)!) as Map)['Rahul|1'];
    expect(r['todoId'], 1);
    expect(r['thread'], 'whatsapp|rahul');
    expect(r['body'], 'Rahul: “At 8?”');
  });

  test('a restored item whose id was taken gets a new one', () async {
    await start([todo(1)]);
    final gone = await cubit.remove(1);
    // Something else takes id 1 meanwhile (an older counter, a computer).
    await store.edit(
      (items, meta) => (
        [...items, todo(1).copyWith(title: 'Other', sourceKey: 'Other|1')],
        meta,
      ),
    );
    await cubit.restore(gone!);
    final items = await stored();
    expect(items.map((i) => i.id).toSet(), {1, 2});
    expect(items.firstWhere((i) => i.sourceKey == 'Rahul|1').id, 2);
  });

  test('"today" moves on at midnight', () async {
    clockNow = DateTime(2026, 10, 3, 23, 59, 59, 900);
    await start([todo(1), todo(2, dayOffset: 1)]);
    expect(cubit.state.today.single.id, 1);

    clockNow = DateTime(2026, 10, 4, 0, 0, 1);
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    expect(cubit.state.now, clockNow);
    expect(cubit.state.today.single.id, 2);
  });

  test('a list that takes too long stops drafting, then shows up', () async {
    await start([todo(1)], timeout: const Duration(milliseconds: 50));
    await cubit.make();
    expect(cubit.state.phase, TodoPhase.idle);
    expect(cubit.state.items, hasLength(1));

    generator.reply.complete();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(cubit.state.items, hasLength(2));
  });
}
