import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/features/echo/data/context/chat_context_store.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/profile/data/paired_computers.dart';
import 'package:project_echo/features/profile/data/week_stats.dart';
import 'package:project_echo/features/profile/presentation/screens/hears_screen.dart';
import 'package:project_echo/features/profile/presentation/screens/you_screen.dart';
import 'package:project_echo/features/profile/presentation/widgets/share_week_sheet.dart';
import 'package:project_echo/features/todo/data/owed_store.dart';
import 'package:project_echo/features/todo/data/todo_item.dart';
import 'package:project_echo/features/todo/data/todo_store.dart';
import 'package:project_echo/features/vault/data/daily_stats.dart';
import 'package:project_echo/features/vault/presentation/widgets/category_pie_chart.dart';

TodoItem _todo(int id, DateTime day, {DateTime? doneAt, String sender = ''}) =>
    TodoItem(
      id: id,
      title: 'x',
      day: day,
      time: null,
      sort: 0,
      sender: sender,
      app: '',
      sourceText: '',
      sourceKey: 'a|$id',
      created: day,
      done: doneAt != null,
      doneAt: doneAt,
    );

void main() {
  final now = DateTime(2026, 11, 8, 20);

  group('WeekStats.summarise', () {
    test('counts each person once, and once per day in the bars', () {
      final w = WeekStats.summarise(
        items: const [],
        replies: const [],
        readByDay: List.filled(7, 0),
        now: now,
        answers: [
          (thread: 'a', at: DateTime(2026, 11, 8, 9)),
          (thread: 'a', at: DateTime(2026, 11, 8, 10)),
          (thread: 'a', at: DateTime(2026, 11, 3, 10)),
          (thread: 'b', at: DateTime(2026, 11, 8, 11)),
        ],
      );
      expect(w.peopleAnswered, 2);
      expect(w.answeredByDay.last, 2);
      expect(w.answeredByDay[1], 1);
    });

    test('ignores answers from before the week', () {
      final w = WeekStats.summarise(
        items: const [],
        replies: const [],
        readByDay: List.filled(7, 0),
        now: now,
        answers: [(thread: 'a', at: DateTime(2026, 11, 1, 10))],
      );
      expect(w.peopleAnswered, 0);
    });

    test('to-dos done of due', () {
      final today = DateTime(2026, 11, 8);
      final w = WeekStats.summarise(
        items: [
          _todo(1, today, doneAt: now),
          _todo(2, today),
          _todo(3, DateTime(2026, 11, 12)),
        ],
        replies: const [],
        readByDay: List.filled(7, 0),
        now: now,
      );
      expect(w.todosDone, 1);
      expect(w.todosDue, 2);
    });
  });

  group('shared picture', () {
    test('its figures hold numbers only', () {
      final week = WeekStats.summarise(
        items: const [],
        replies: const [],
        readByDay: List.filled(7, 0),
        now: now,
        answers: [(thread: 'Rohan', at: DateTime(2026, 11, 8, 9))],
      );
      for (final (big, label) in weekCardFigures(week, 4)) {
        expect(big, matches(RegExp(r'^[\d/]+( days?)?$')));
        expect(label, isNot(contains('Rohan')));
      }
    });
  });

  group('HearsSummary', () {
    DayStats day(Map<String, int> apps) =>
        DayStats(now, List.filled(24, 0), apps);

    test('adds up the week and names the busiest', () {
      final s = HearsSummary.of([
        day({'Work': 5, 'Friends': 3}),
        day({'Work': 1, 'Groups': 2}),
      ], const {});
      expect(s.title, '3 apps · 11 signals this week');
      expect(s.busiest, 'Work, Friends and Groups are the busiest');
    });

    test('leaves out excluded apps', () {
      final s = HearsSummary.of(
        [
          day({'Work': 5, 'Secret': 30}),
        ],
        {'Secret'},
      );
      expect(s.apps, 1);
      expect(s.top, ['Work']);
      expect(s.busiest, 'Work is the busiest');
    });
  });

  group('wheel', () {
    test('drops All, empties and excluded, busiest first', () {
      final counts = wheelCounts(
        {'All': 9, 'A': 1, 'B': 8, 'C': 0, 'D': 3},
        {'D'},
      );
      expect(counts.keys.toList(), ['B', 'A']);
    });

    test('seven distinct colour slots', () {
      expect(List.generate(7, (i) => sliceColorIndex(i, 7)).toSet().length, 7);
    });

    test('the last slice never matches the first it touches', () {
      expect(sliceColorIndex(7, 8), isNot(sliceColorIndex(0, 8)));
      expect(sliceColorIndex(14, 15), isNot(sliceColorIndex(0, 15)));
    });
  });

  group('PairedComputers.merged', () {
    const mac = PairedComputer(host: '10.0.0.2:8790', name: 'Mac', token: 't');

    test('keeps earlier computers when another pairs', () {
      final list = PairedComputers.merged(
        [mac],
        host: '10.0.0.3:8790',
        name: 'iMac',
        token: 'u',
      );
      expect(list.map((c) => c.name), ['Mac', 'iMac']);
    });

    test('a computer with a new address replaces its entry', () {
      final list = PairedComputers.merged(
        [mac],
        host: '10.0.0.9:8790',
        name: 'Mac',
        token: 't',
      );
      expect(list.single.host, '10.0.0.9:8790');
    });

    test('nothing paired leaves the list alone', () {
      expect(
        PairedComputers.merged([mac], host: null, name: null, token: null),
        [mac],
      );
    });

    test('bad stored data reads as empty', () {
      expect(PairedComputers.decode('not json'), isEmpty);
    });
  });

  group('OwedStore', () {
    RawData latest(
      DateTime at, {
      bool group = false,
      String sender = 'Karan',
    }) => RawData()
      ..source = 'WhatsApp'
      ..sender = sender
      ..content = 'hi'
      ..timestamp = at
      ..threadTitle = sender
      ..isGroup = group;

    final asked = DateTime(2026, 11, 5, 10);
    const ask = 'Can you send the invoice?';

    test('an ask with nothing back since is owed', () {
      final owed = OwedStore.select([
        OwedCandidate(MyTurn(asked, ask), latest(DateTime(2026, 11, 4))),
      ], now);
      expect(owed.single.name, 'Karan');
      expect(owed.single.what, ask);
      expect(owed.single.askedLabel(now), 'Asked Thursday, 3 days');
    });

    test('an answer since clears it', () {
      expect(
        OwedStore.select([
          OwedCandidate(MyTurn(asked, ask), latest(DateTime(2026, 11, 6))),
        ], now),
        isEmpty,
      );
    });

    test('a group is nobody in particular', () {
      expect(
        OwedStore.select([
          OwedCandidate(
            MyTurn(asked, ask),
            latest(DateTime(2026, 11, 4), group: true),
          ),
        ], now),
        isEmpty,
      );
    });

    test('too fresh, too old, or not asking is not owed', () {
      expect(OwedStore.isOpenAsk(MyTurn(now, ask), now), isFalse);
      expect(
        OwedStore.isOpenAsk(MyTurn(DateTime(2026, 10, 1), ask), now),
        isFalse,
      );
      expect(OwedStore.isOpenAsk(MyTurn(asked, 'ok thanks'), now), isFalse);
      expect(OwedStore.isOpenAsk(MyTurn(asked, ask), now), isTrue);
    });

    test('nothing at all means nothing to show', () {
      expect(OwedStore.select(const [], now), isEmpty);
    });
  });

  group('to-do items', () {
    test('who asked and where', () {
      final item = _todo(1, now, sender: 'Rahul · College gang');
      expect(item.asker, 'Rahul');
      expect(item.chat, 'College gang');
      expect(_todo(2, now, sender: 'Amma').chat, isNull);
    });

    test('an item stored by an older version still reads', () {
      final items = TodoStore.decodeItems(
        '[{"id":1,"title":"Call","day":"2026-11-08"}]',
      );
      expect(items.single.title, 'Call');
      expect(items.single.sender, '');
      expect(items.single.sort, TodoItem.noTimeSort);
    });

    test('one unreadable item does not cost the list', () {
      final items = TodoStore.decodeItems(
        '[{"title":"no id"},{"id":2,"title":"Fine","day":"2026-11-08"}]',
      );
      expect(items.map((i) => i.id), [2]);
    });

    test('an unreadable list is empty, not a crash', () {
      expect(TodoStore.decodeItems('{oops'), isEmpty);
    });

    test('the native widget fields survive a round trip', () {
      final json = _todo(1, DateTime(2026, 11, 8)).toJson();
      expect(json.keys, containsAll(['id', 'title', 'day', 'time', 'done']));
    });
  });
}
