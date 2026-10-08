import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/relevance/briefing_selection.dart';
import 'package:project_echo/features/todo/data/todo_item.dart';
import 'package:project_echo/features/todo/data/todo_planner.dart';

// Sat 26 Sep 2026.
DateTime at(int day, int hour, [int minute = 0]) =>
    DateTime(2026, 9, day, hour, minute);
final now = at(26, 14);

RawData note(
  String sender,
  String content,
  DateTime receivedAt, {
  String source = 'Whatsapp',
}) => RawData()
  ..source = source
  ..sender = sender
  ..content = content
  ..timestamp = receivedAt;

final neha = note(
  'Neha',
  'Client demo is tomorrow at 6:30 PM, please prep the deck',
  at(25, 18, 40),
  source: 'Slack',
);
final plumber = note(
  'Landlord',
  'Plumber coming tomorrow between 4 to 6 PM',
  at(25, 22, 30),
  source: 'Sms',
);
final didi = note('Didi', 'Can you pick up medicines for dad?', at(26, 12, 30));
final dentist = note(
  'Dr Mehta',
  'Your appointment is tomorrow at 11:00 AM',
  at(26, 9),
);

List<BriefingItem> pick(List<RawData> entries) =>
    selectForBriefing(entries, now, limit: 25);

void main() {
  group('parsing replies', () {
    test('make: tolerates fences and prose, drops malformed entries', () {
      const reply =
          'Here you go:\n```json\n[{"t": "Prep the deck", "s": 2},'
          ' {"t": "", "s": 1}, {"x": 1}, {"t": "Call Didi", "s": "3"}]\n```';
      expect(parseMakeReply(reply), [
        (title: 'Prep the deck', source: 2, when: null),
      ]);
      expect(parseMakeReply('not json'), isEmpty);
    });

    test('update: add and change', () {
      final r = parseUpdateReply(
        '{"add": [{"t": "Gym session", "s": 2}], "change": [{"id": 3, "s": 1}]}',
      );
      expect(r.add, [(title: 'Gym session', source: 2, when: null)]);
      expect(r.change, [(id: 3, source: 1)]);
      expect(parseUpdateReply('{}').add, isEmpty);
    });
  });

  group('make', () {
    test('day and time come from the notification, resolved against now', () {
      final cands = pick([neha, plumber, didi, dentist]);
      final bySender = {
        for (var i = 0; i < cands.length; i++) cands[i].entry.sender: i + 1,
      };
      final items = applyMake(
        existing: const [],
        candidates: cands,
        todos: [
          (
            title: 'Prep the deck for the client demo',
            source: bySender['Neha']!,
            when: null,
          ),
          (
            title: 'Be home for the plumber',
            source: bySender['Landlord']!,
            when: null,
          ),
          (
            title: 'Pick up medicines for dad',
            source: bySender['Didi']!,
            when: null,
          ),
          (
            title: 'Dentist appointment',
            source: bySender['Dr Mehta']!,
            when: null,
          ),
        ],
        firstId: 1,
        now: now,
      );
      final byTitle = {for (final i in items) i.title: i};

      // Neha said "tomorrow" yesterday: it's today.
      expect(byTitle['Prep the deck for the client demo']!.day, at(26, 0));
      expect(byTitle['Prep the deck for the client demo']!.time, '6:30 PM');
      expect(
        byTitle['Prep the deck for the client demo']!.sourceText,
        'Client demo is today at 6:30 PM, please prep the deck',
      );
      expect(byTitle['Be home for the plumber']!.time, '4–6 PM');
      expect(byTitle['Pick up medicines for dad']!.time, isNull);
      expect(byTitle['Pick up medicines for dad']!.sort, TodoItem.noTimeSort);
      expect(byTitle['Dentist appointment']!.day, at(27, 0));
      expect(byTitle['Dentist appointment']!.time, '11 AM');
      expect(items.map((i) => i.id), [1, 2, 3, 4]);
    });

    test(
      'out-of-range sources are ignored and a notification is used once',
      () {
        final cands = pick([didi]);
        final items = applyMake(
          existing: const [],
          candidates: cands,
          todos: [
            (title: 'A', source: 1, when: null),
            (title: 'B', source: 1, when: null),
            (title: 'C', source: 9, when: null),
          ],
          firstId: 1,
          now: now,
        );
        expect(items.map((i) => i.title), ['A']);
      },
    );
  });

  group('update', () {
    late List<TodoItem> list;
    setUp(() {
      final cands = pick([neha, didi]);
      final nehaIdx = cands.indexWhere((c) => c.entry.sender == 'Neha') + 1;
      final didiIdx = cands.indexWhere((c) => c.entry.sender == 'Didi') + 1;
      list = applyMake(
        existing: const [],
        candidates: cands,
        todos: [
          (
            title: 'Prep the deck for the client demo',
            source: nehaIdx,
            when: null,
          ),
          (title: 'Pick up medicines for dad', source: didiIdx, when: null),
        ],
        firstId: 1,
        now: now,
      );
      // Didi's item was ticked off.
      list = [
        for (final i in list) i.sender == 'Didi' ? i.copyWith(done: true) : i,
      ];
    });

    test('adds new items, amends changed ones, never removes anything', () {
      final demoId = list.firstWhere((i) => i.sender == 'Neha').id;
      final moved = note(
        'Neha',
        'Demo pushed to 7 PM, same deck',
        at(26, 14, 20),
        source: 'Slack',
      );
      final gym = note(
        'Gym',
        'Your trainer session is tomorrow 7 AM',
        at(26, 14, 25),
        source: 'Sms',
      );
      final fresh = pick([moved, gym]);
      final movedIdx = fresh.indexWhere((c) => c.entry.sender == 'Neha') + 1;
      final gymIdx = fresh.indexWhere((c) => c.entry.sender == 'Gym') + 1;

      final next = applyUpdate(
        existing: list,
        candidates: fresh,
        add: [
          (title: 'Gym session with your trainer', source: gymIdx, when: null),
        ],
        change: [(id: demoId, source: movedIdx)],
        firstId: 3,
        now: at(26, 14, 30),
      );

      expect(next, hasLength(3));
      final demo = next.firstWhere((i) => i.id == demoId);
      expect(demo.title, 'Prep the deck for the client demo');
      expect(demo.time, '7 PM');
      expect(demo.movedFrom, '6:30 PM');
      expect(next.firstWhere((i) => i.sender == 'Didi').done, isTrue);
      final gymItem = next.firstWhere((i) => i.sender == 'Gym');
      expect(gymItem.isNew, isTrue);
      expect(gymItem.day, at(27, 0));
      expect(gymItem.id, 3);
    });

    test('a notification already on the list is not added again', () {
      final next = applyUpdate(
        existing: list,
        candidates: pick([didi]),
        add: [(title: 'Medicines again', source: 1, when: null)],
        change: const [],
        firstId: 3,
        now: now,
      );
      expect(next, hasLength(2));
    });

    test('the previous update\'s "new" marks are cleared', () {
      final first = applyUpdate(
        existing: list,
        candidates: pick([dentist]),
        add: [(title: 'Dentist', source: 1, when: null)],
        change: const [],
        firstId: 3,
        now: now,
      );
      final second = applyUpdate(
        existing: first,
        candidates: const [],
        add: const [],
        change: const [],
        firstId: 4,
        now: now,
      );
      expect(first.where((i) => i.isNew), hasLength(1));
      expect(second.where((i) => i.isNew), isEmpty);
    });
  });

  group('keeping the list short', () {
    test('a model reply is capped', () {
      final many = [
        for (var i = 1; i <= 20; i++) '{"t": "Task $i", "s": $i}',
      ].join(',');
      expect(parseMakeReply('[$many]'), hasLength(maxListItems));
    });

    test(
      'without a model, dated notifications are preferred and the list is capped',
      () {
        final notes = [
          for (var i = 0; i < 10; i++)
            note('Undated $i', 'Hello number $i', at(26, 12, i)),
          for (var i = 0; i < 4; i++)
            note('Dated $i', 'Meet tomorrow at ${i + 9} AM', at(26, 10, i)),
        ];
        final cands = pick(notes);
        final picks = localPicks(cands);
        expect(picks, hasLength(maxListItems));
        final firstFour = picks.take(4).map((i) => cands[i].entry.sender);
        expect(firstFour.every((s) => s.startsWith('Dated')), isTrue);
      },
    );
  });

  test('prompt lines are numbered, labelled and use corrected day words', () {
    final text = numberedLines(pick([neha]), now);
    expect(text, startsWith('1. [Today (Sat 26 Sep), 6:30 PM] Neha (Slack): '));
    expect(text, contains('Client demo is today at 6:30 PM'));
  });

  test('local titles use the first sentence', () {
    expect(
      localTitle(
        note('X', 'Plumber coming tomorrow. Be home.', at(25, 20)),
        now,
      ),
      'Plumber coming today',
    );
  });

  test('items survive a JSON round trip', () {
    final item = applyMake(
      existing: const [],
      candidates: pick([neha]),
      todos: [(title: 'Prep the deck', source: 1, when: null)],
      firstId: 7,
      now: now,
    ).single.copyWith(done: true, movedFrom: '6 PM');
    final back = TodoItem.fromJson(item.toJson());
    expect(back.toJson(), item.toJson());
  });

  group('a message with many tasks', () {
    // Received Friday evening, about Saturday.
    final list = note(
      'Neha',
      'For tomorrow: send me the deck by 4 PM, call the vendor at 11 AM, '
          'book the room, and remind Priya about the invoice',
      at(25, 19),
      source: 'Slack',
    );

    List<TodoItem> make(List<NewTodo> todos) => applyMake(
      existing: const [],
      candidates: pick([list]),
      todos: todos,
      firstId: 1,
      now: now,
    );

    test(
      'more than three tasks become one item each, with their own times',
      () {
        final items = make([
          (title: 'Send Neha the deck', source: 1, when: 'by 4 PM'),
          (title: 'Call the vendor', source: 1, when: 'at 11 AM'),
          (title: 'Book the room', source: 1, when: null),
          (title: 'Remind Priya about the invoice', source: 1, when: null),
        ]);
        expect(items.map((i) => i.title), [
          'Send Neha the deck',
          'Call the vendor',
          'Book the room',
          'Remind Priya about the invoice',
        ]);
        expect(items.map((i) => i.time), ['4 PM', '11 AM', null, null]);
        // "by 4 PM" names no day, so it's on the day the message is about.
        expect(items.every((i) => i.day == DateTime(2026, 9, 26)), isTrue);
        expect(items.map((i) => i.sourceKey).toSet(), hasLength(4));
      },
    );

    test('three tasks or fewer stay one item, timed by the whole message', () {
      final items = make([
        (title: 'Send Neha the deck', source: 1, when: 'by 4 PM'),
        (title: 'Call the vendor', source: 1, when: 'at 11 AM'),
      ]);
      expect(items.single.title, 'Send Neha the deck');
    });

    test('a split message already on the list is not added again', () {
      final first = make([
        for (final t in ['A', 'B', 'C', 'D']) (title: t, source: 1, when: null),
      ]);
      final again = applyMake(
        existing: first,
        candidates: pick([list]),
        todos: [(title: 'E', source: 1, when: null)],
        firstId: 5,
        now: now,
      );
      expect(again, hasLength(4));
    });

    test('the cap counts messages, not items', () {
      final reply =
          '[${[for (var i = 0; i < 5; i++) '{"t": "Part $i", "s": 1}'].join(',')},'
          '${[for (var s = 2; s <= 9; s++) '{"t": "Other $s", "s": $s}'].join(',')}]';
      final todos = parseMakeReply(reply);
      expect(todos.where((t) => t.source == 1), hasLength(5));
      expect(todos.map((t) => t.source).toSet(), hasLength(maxListItems));
    });

    test('a time with its own day keeps that day', () {
      final w = partWindow(
        'Monday at 9 AM',
        at(25, 19),
        pick([list]).single.window,
      )!;
      expect(w.start, DateTime(2026, 9, 28, 9));
    });

    test('long list-like messages reach the model in full', () {
      expect(looksLikeList('1. deck\n2. vendor\n3. room\n4. invoice'), isTrue);
      expect(looksLikeList('call me when you can'), isFalse);
    });
  });
}
