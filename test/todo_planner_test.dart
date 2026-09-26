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
      expect(parseMakeReply(reply), [(title: 'Prep the deck', source: 2)]);
      expect(parseMakeReply('not json'), isEmpty);
    });

    test('update: add and change', () {
      final r = parseUpdateReply(
        '{"add": [{"t": "Gym session", "s": 2}], "change": [{"id": 3, "s": 1}]}',
      );
      expect(r.add, [(title: 'Gym session', source: 2)]);
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
          ),
          (title: 'Be home for the plumber', source: bySender['Landlord']!),
          (title: 'Pick up medicines for dad', source: bySender['Didi']!),
          (title: 'Dentist appointment', source: bySender['Dr Mehta']!),
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
            (title: 'A', source: 1),
            (title: 'B', source: 1),
            (title: 'C', source: 9),
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
          (title: 'Prep the deck for the client demo', source: nehaIdx),
          (title: 'Pick up medicines for dad', source: didiIdx),
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
        add: [(title: 'Gym session with your trainer', source: gymIdx)],
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
        add: [(title: 'Medicines again', source: 1)],
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
        add: [(title: 'Dentist', source: 1)],
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
      todos: [(title: 'Prep the deck', source: 1)],
      firstId: 7,
      now: now,
    ).single.copyWith(done: true, movedFrom: '6 PM');
    final back = TodoItem.fromJson(item.toJson());
    expect(back.toJson(), item.toJson());
  });
}
