import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/core/services/phone_actions.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/features/desktop/presentation/today/reply_suggestions.dart';
import 'package:project_echo/features/desktop/presentation/today/today_detail.dart';
import 'package:project_echo/features/desktop/presentation/today/today_list.dart';
import 'package:project_echo/features/desktop/presentation/today/today_logic.dart';
import 'package:project_echo/features/desktop/presentation/today/today_rail.dart';
import 'package:project_echo/features/echo/data/context/chat_context_store.dart';
import 'package:project_echo/features/echo/data/home/home_feed.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/reply/reply_sender.dart';
import 'package:project_echo/features/todo/data/todo_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

RawData msg(String sender, String text, DateTime at, {String? thread}) =>
    RawData()
      ..source = 'WhatsApp'
      ..sender = sender
      ..content = text
      ..timestamp = at
      ..thread = thread;

PhoneAction reply(
  ActionState state,
  DateTime at, {
  String? outcome,
  String thread = 't1',
}) => PhoneAction(
  id: 'a1',
  body: {'kind': 'reply', 'thread': thread, 'text': 'On it', 'to': 'Rahul'},
  state: state,
  at: at,
  outcome: outcome,
);

void main() {
  final now = DateTime(2026, 10, 3, 16, 12);

  group('header words', () {
    test('says who is waiting', () {
      expect(peopleWaiting(0), ('No one', ' is waiting on you'));
      expect(peopleWaiting(1), ('One person', ' is waiting on you'));
      expect(peopleWaiting(5), ('Five people', ' are waiting on you'));
      expect(peopleWaiting(14), ('14 people', ' are waiting on you'));
    });

    test('dates and numbers', () {
      expect(longDate(now), 'Saturday, 3 October');
      expect(greetingAt(19), 'Good evening');
      expect(withCommas(2045), '2,045');
      expect(withCommas(18), '18');
    });

    test('a briefing takes at least a minute', () {
      expect(briefingMinutes('Short one.'), 1);
      expect(briefingMinutes(List.filled(400, 'word').join(' ')), 3);
    });
  });

  test('a promise reads back in the second person', () {
    expect(
      promiseLine('Priya', 'I’ll share the photos tonight'),
      'You told Priya you’d share the photos tonight.',
    );
    expect(
      promiseLine('Priya', 'Let me check by 5'),
      'You told Priya: “Let me check by 5”',
    );
  });

  group('the conversation', () {
    final rahul = msg(
      'Rahul',
      'Need to know by 8',
      now.subtract(const Duration(minutes: 14)),
      thread: 't1',
    );
    final sneha = msg(
      'Sneha',
      'Booked the table',
      now.subtract(const Duration(minutes: 31)),
      thread: 't1',
    );

    test('merges the owner’s turns in by time and marks the picked one', () {
      final lines = conversation(
        [rahul, sneha],
        [MyTurn(now.subtract(const Duration(minutes: 22)), 'Who is coming?')],
        picked: rahul,
      );
      expect(lines.map((l) => l.who), ['Sneha', 'You', 'Rahul']);
      expect(lines[1].mine, isTrue);
      expect(lines.where((l) => l.picked).single.text, 'Need to know by 8');
    });

    test('keeps the picked message when cutting it short', () {
      final many = [
        for (var i = 0; i < 12; i++)
          msg('Kiran', 'later $i', now.add(Duration(minutes: i)), thread: 't1'),
      ];
      final lines = conversation([...many, rahul], const [], picked: rahul);
      expect(lines, hasLength(8));
      expect(lines.first.picked, isTrue);
    });

    test('a promise highlights the owner’s own words', () {
      final said = MyTurn(now, 'I’ll send it by 5');
      final promise = msg('You', said.text, said.at);
      final lines = conversation(
        [rahul],
        [said],
        picked: promise,
        pickedMine: true,
      );
      expect(lines.last.picked && lines.last.mine, isTrue);
      expect(lines.where((l) => l.picked), hasLength(1));
    });
  });

  group('replies sent from here', () {
    final rahul = msg('Rahul', 'Coming?', now, thread: 't1');

    test('only a reply to that chat since the message counts', () {
      final before = reply(
        ActionState.done,
        now.subtract(const Duration(minutes: 1)),
      );
      final after = reply(
        ActionState.waiting,
        now.add(const Duration(minutes: 1)),
      );
      final elsewhere = reply(
        ActionState.done,
        now.add(const Duration(minutes: 2)),
        thread: 't2',
      );
      expect(replyTo([before, elsewhere], rahul), isNull);
      expect(replyTo([before, after, elsewhere], rahul), after);
    });

    test('says how it is going', () {
      expect(
        replyStatus(reply(ActionState.waiting, now), now).$1,
        ReplyStage.going,
      );
      expect(
        replyStatus(
          reply(ActionState.collected, now),
          now.add(const Duration(seconds: 41)),
        ),
        (ReplyStage.slow, 'Waiting for your phone. Is it on the same Wi-Fi?'),
      );
      expect(replyStatus(reply(ActionState.done, now, outcome: 'sent'), now), (
        ReplyStage.sent,
        'Sent to Rahul · 4:12 PM',
      ));
      expect(
        replyStatus(reply(ActionState.done, now, outcome: 'ready'), now).$1,
        ReplyStage.ready,
      );
      expect(
        replyStatus(reply(ActionState.failed, now), now).$2,
        'Your phone couldn’t send it',
      );
    });
  });

  test('marks are kept for the day only', () {
    const raw = '{"day":"2026-10-03","ids":["a","b"]}';
    expect(HandledMarks.decode(raw, now), {'a', 'b'});
    expect(HandledMarks.decode(raw, now.add(const Duration(days: 1))), isEmpty);
    expect(HandledMarks.decode('nonsense', now), isEmpty);
  });

  test('rest of today: timed to-dos and reminders still to come', () {
    final today = DateTime(2026, 10, 3);
    TodoItem todo(int id, String? time, {bool done = false}) => TodoItem(
      id: id,
      title: 'To-do $id',
      day: today,
      time: time,
      sort: id,
      sender: '',
      app: '',
      sourceText: '',
      sourceKey: 'k$id',
      done: done,
      created: today,
    );
    final events = restOfToday(
      [
        todo(1, '6 PM'),
        todo(2, '9 AM'),
        todo(3, null),
        todo(4, '8 PM', done: true),
      ],
      [
        (DateTime(2026, 10, 3, 17, 40), 'Rahul'),
        (DateTime(2026, 10, 4, 9), 'Tomorrow'),
      ],
      now,
    );
    expect(events.map((e) => e.label), ['Reminder · Rahul', 'To-do 1']);
    expect(events.first.reminder, isTrue);
  });

  test('reminder titles come from the store', () {
    expect(reminderTitles('{"k1":{"at":1,"title":"Rahul"},"k2":{"at":2}}'), {
      'k1': 'Rahul',
    });
  });

  group('reply suggestions', () {
    test('reads an array, or an object holding one', () {
      expect(
        ReplySuggestions.parse('```json\n["Yes!", "\\"No\\"", "Yes!"]\n```'),
        ['Yes!', 'No'],
      );
      expect(ReplySuggestions.parse('{"replies": ["A", "B", "C", "D"]}'), [
        'A',
        'B',
        'C',
      ]);
      expect(ReplySuggestions.parse(null), isEmpty);
      expect(ReplySuggestions.parse('sorry'), isEmpty);
    });

    test('always three, topped up with plain ones', () {
      final call = msg('Amma', 'Call when you’re free tonight.', now);
      expect(ReplySuggestions.local(call).first, 'Will call you soon');
      final ask = msg('Mahesh', 'Please confirm by 6', now);
      final got = ReplySuggestions.fill(['Confirmed, 2 PM works'], ask);
      expect(got, hasLength(3));
      expect(got.first, 'Confirmed, 2 PM works');
      expect(
        ReplySuggestions.fill(const [], msg('X', 'ok', now)),
        hasLength(3),
      );
    });
  });

  testWidgets('the three columns lay out in light and dark', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1128, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final rahul =
        msg(
            'Rahul',
            'I can drive Friday. Need to know by 8 tonight.',
            now,
            thread: 't1',
          )
          ..isGroup = true
          ..threadTitle = 'College gang'
          ..addressed = 'reply';
    final gang = BusyGroup(name: 'College gang', count: 6, messages: [rahul]);
    final promise = Promise(
      chat: rahul,
      turn: MyTurn(now, 'I’ll share the photos tonight'),
    );
    final items = [
      TriageItem.waiting(rahul),
      TriageItem.promise(promise),
      TriageItem.group(gang),
    ];
    final actions = TodayActions(
      send: (_) {},
      remind: () {},
      addToList: () {},
      handle: () {},
      catchUp: () {},
      leaveReply: () {},
    );
    final focus = FocusNode();
    addTearDown(focus.dispose);
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      for (final item in items) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Material(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 380,
                    child: TodayList(
                      items: items,
                      selected: item.id,
                      handled: const {},
                      summaries: const {},
                      onSelect: (_) {},
                    ),
                  ),
                  Expanded(
                    child: TodayDetail(
                      item: item,
                      lines: conversation([rahul], const [], picked: rahul),
                      now: now,
                      marked: false,
                      reply: null,
                      route: ReplyRoute.send,
                      remindAt: now.add(const Duration(hours: 3)),
                      reminding: null,
                      onList: false,
                      summary: null,
                      replyFocus: focus,
                      actions: actions,
                    ),
                  ),
                  SizedBox(
                    width: 300,
                    child: TodayRail(
                      events: [
                        RailEvent(
                          now.add(const Duration(hours: 2)),
                          'Call Amma',
                        ),
                      ],
                      now: now,
                      briefing: 'Good evening.',
                      briefingAt: now,
                      playing: false,
                      onPlay: () {},
                      week: null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    }
    expect(find.text('Catch me up in Ask'), findsOneWidget);
  });
}
