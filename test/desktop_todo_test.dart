import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/features/desktop/presentation/todo/board_logic.dart';
import 'package:project_echo/features/desktop/presentation/todo/desktop_todo_board.dart';
import 'package:project_echo/features/todo/data/todo_item.dart';
import 'package:project_echo/features/todo/presentation/cubit/todo_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Sat 3 Oct 2026, 4:12 PM.
final now = DateTime(2026, 10, 3, 16, 12);

TodoItem item(
  int id, {
  int dayOffset = 0,
  String? time,
  int sort = TodoItem.noTimeSort,
  bool done = false,
  String? key,
}) => TodoItem(
  id: id,
  title: 'Item $id',
  day: DateTime(2026, 10, 3 + dayOffset),
  time: time,
  sort: sort,
  sender: 'Priya',
  app: 'Slack',
  sourceText: 'Can you book the cab?',
  sourceKey: key ?? 'Priya|$id',
  created: now,
  done: done,
);

void main() {
  group('columns', () {
    test('today, tomorrow, and everything after under Later', () {
      expect(BoardColumn.of(item(1), now), BoardColumn.today);
      expect(BoardColumn.of(item(2, dayOffset: 1), now), BoardColumn.tomorrow);
      expect(BoardColumn.of(item(3, dayOffset: 2), now), BoardColumn.later);
      expect(BoardColumn.of(item(4, dayOffset: 30), now), BoardColumn.later);
    });

    test('days already gone are not on the board', () {
      expect(BoardColumn.of(item(1, dayOffset: -1), now), isNull);
      final items = [item(1, dayOffset: -1, done: true), item(2)];
      expect(itemsIn(BoardColumn.today, items, now).map((i) => i.id), [2]);
    });

    test('a card dropped on Later goes to the day after tomorrow', () {
      expect(BoardColumn.today.dayFrom(now), DateTime(2026, 10, 3));
      expect(BoardColumn.tomorrow.dayFrom(now), DateTime(2026, 10, 4));
      expect(BoardColumn.later.dayFrom(now), DateTime(2026, 10, 5));
    });

    test('done sinks to the bottom; the rest go by day, then time', () {
      final items = [
        item(1, sort: 600, done: true),
        item(2),
        item(3, sort: 18 * 60, time: '6:00 PM'),
        item(4, sort: 9 * 60, time: '9:00 AM'),
      ];
      expect(itemsIn(BoardColumn.today, items, now).map((i) => i.id), [
        4,
        3,
        2,
        1,
      ]);
      final later = [item(5, dayOffset: 4, sort: 60), item(6, dayOffset: 2)];
      expect(itemsIn(BoardColumn.later, later, now).map((i) => i.id), [6, 5]);
    });

    test('counts what is left under the name', () {
      expect(columnNote(BoardColumn.today, now, const []), 'Saturday');
      expect(
        columnNote(BoardColumn.today, now, [item(1), item(2, done: true)]),
        'Saturday · 1 left',
      );
      expect(
        columnNote(BoardColumn.tomorrow, now, [item(1, done: true)]),
        'Sunday · all done',
      );
    });
  });

  group('cards', () {
    test('the parts of a split message share one card', () {
      final items = [
        item(1),
        item(2, key: 'Priya|99#1'),
        item(3),
        item(4, key: 'Priya|99#2'),
      ];
      expect(cardsOf(items).map((c) => c.map((i) => i.id).toList()).toList(), [
        [1],
        [2, 4],
        [3],
      ]);
    });

    test('a lone part, or items without a key, stay on their own', () {
      final items = [
        item(1, key: 'Priya|99#1'),
        item(2, key: ''),
        item(3, key: ''),
      ];
      expect(cardsOf(items).length, 3);
    });
  });

  group('reminders', () {
    test('offers Echo’s time only for what has one and isn’t set', () {
      final items = [
        item(1, time: '8:00 PM', sort: 20 * 60),
        item(2, time: '9:00 PM', sort: 21 * 60),
        item(3),
        item(4, time: '7:00 PM', sort: 19 * 60, done: true),
      ];
      final offers = offersIn(items, {
        'Priya|2': DateTime(2026, 10, 3, 20),
      }, now);
      expect(offers.map((o) => o.$1.id), [1]);
      expect(offers.single.$2, DateTime(2026, 10, 3, 19, 40));
    });
  });

  group('days', () {
    test('short within the week, dated after it', () {
      expect(shortDay(DateTime(2026, 10, 6), now), 'Tue');
      expect(shortDay(DateTime(2026, 10, 12), now), '12 Oct');
      expect(dayLabel(DateTime(2026, 10, 6)), 'Tue 6 Oct');
    });

    test('a clock change doesn’t lose a day', () {
      // Clocks change overnight in many places around here.
      expect(
        daysBetween(DateTime(2026, 10, 24, 23), DateTime(2026, 10, 26)),
        2,
      );
      expect(daysBetween(DateTime(2026, 3, 28, 1), DateTime(2026, 3, 29)), 1);
    });
  });

  group('the board', () {
    for (final dark in [false, true]) {
      testWidgets('lays out, opens and picks (${dark ? 'dark' : 'light'})', (
        tester,
      ) async {
        // Wide enough for the test font, whose letters are all square.
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        SharedPreferences.setMockInitialValues({});
        final today = DateTime.now();
        TodoItem on(int id, int offset, {String? key, bool done = false}) =>
            TodoItem(
              id: id,
              title: 'Thing $id',
              day: DateTime(today.year, today.month, today.day + offset),
              time: '11:59 PM',
              sort: 23 * 60 + 59,
              sender: 'Mahesh',
              app: 'WhatsApp',
              sourceText: 'Sunday slots: 10 AM and 2 PM.',
              sourceKey: key ?? 'Mahesh|$id',
              created: today,
              done: done,
            );
        final cubit = _ListOf([
          on(1, 0),
          on(2, 0, done: true),
          on(3, 1),
          on(4, 1, key: 'Priya|9#1'),
          on(5, 1, key: 'Priya|9#2'),
          on(6, 3),
        ]);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
            home: Scaffold(
              body: Row(
                children: [
                  const SizedBox(width: 232),
                  Expanded(
                    child: BlocProvider<TodoCubit>.value(
                      value: cubit,
                      child: const DesktopTodoBoard(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Today'), findsOneWidget);
        expect(find.text('Later'), findsOneWidget);
        expect(find.text('2 things from Mahesh'), findsOneWidget);

        await tester.tap(find.text('Thing 1'));
        await tester.pumpAndSettle();
        expect(find.text('Delete').hitTestable(), findsOneWidget);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.tap(find.text('Thing 3'));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();
        expect(find.text('1 picked'), findsOneWidget);

        final drag = await tester.startGesture(
          tester.getCenter(find.text('Thing 1')),
          kind: PointerDeviceKind.mouse,
        );
        await drag.moveBy(const Offset(30, 0));
        await tester.pump();
        await drag.moveTo(tester.getCenter(find.text('Tomorrow')));
        await tester.pump();
        await drag.up();
        await tester.pumpAndSettle();
        expect(find.text('Moved to tomorrow'), findsOneWidget);
        final queued = (await SharedPreferences.getInstance()).getString(
          'desktop_phone_actions_v1',
        );
        expect(queued, contains('todo_move'));
      });
    }
  });
}

/// A list that's already loaded, for pumping the board without the phone.
class _ListOf extends Cubit<TodoState> implements TodoCubit {
  _ListOf(List<TodoItem> items)
    : super(TodoState(now: DateTime.now(), loaded: true, items: items));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
