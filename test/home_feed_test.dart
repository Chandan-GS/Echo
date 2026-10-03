import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/features/echo/data/context/addressed.dart';
import 'package:project_echo/features/echo/data/context/chat_context_store.dart';
import 'package:project_echo/features/echo/data/home/group_summaries.dart';
import 'package:project_echo/features/echo/data/home/home_feed.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';

// Sat 3 Oct 2026.
DateTime at(int hour, [int minute = 0]) => DateTime(2026, 10, 3, hour, minute);
final now = at(16, 12);

RawData msg(
  String sender,
  String content,
  DateTime when, {
  required String thread,
  String? title,
  bool group = false,
  Addressed? addressed = Addressed.direct,
}) => RawData()
  ..source = 'Whatsapp'
  ..sender = sender
  ..content = content
  ..timestamp = when
  ..thread = thread
  ..threadTitle = title ?? sender
  ..isGroup = group
  ..addressed = addressed?.name;

RawData gang(String sender, String content, DateTime when, {Addressed? a}) =>
    msg(
      sender,
      content,
      when,
      thread: 'com.whatsapp:gang',
      title: 'College gang',
      group: true,
      addressed: a ?? Addressed.group,
    );

MyTurns turns(Map<String, List<(DateTime, String)>> byThread) => MyTurns({
  for (final e in byThread.entries)
    e.key: [for (final (t, x) in e.value) MyTurn(t, x)],
});

const noTurns = MyTurns({});

void main() {
  group('Needs you', () {
    test('the newest message from each chat that wants the owner', () {
      final feed = HomeFeed.summarise(
        [
          msg('Amma', 'Call when you are free', at(13, 39), thread: 'wa:amma'),
          msg('Amma', 'Are you eating?', at(12), thread: 'wa:amma'),
          gang(
            'Rahul',
            'Need to know by 8 tonight',
            at(15, 58),
            a: Addressed.reply,
          ),
          gang('Sneha', 'Booked the table', at(15, 55)),
        ],
        noTurns,
        now,
      );
      expect(feed.needsYou.map((e) => e.content), [
        'Need to know by 8 tonight',
        'Call when you are free',
      ]);
    });

    test('a chat the owner has written in since is not waiting', () {
      final feed = HomeFeed.summarise(
        [
          msg('Amma', 'Call when you are free', at(13, 39), thread: 'wa:amma'),
          msg('Amma', 'Are you eating?', at(12), thread: 'wa:amma'),
        ],
        turns({
          'wa:amma': [(at(14), 'Yes, will call at 9')],
        }),
        now,
      );
      expect(feed.needsYou, isEmpty);
    });

    test('only today, and nothing that is not a chat', () {
      final yesterday = DateTime(2026, 10, 2, 22);
      final feed = HomeFeed.summarise(
        [
          msg('Ravi', 'Water the plants?', yesterday, thread: 'wa:ravi'),
          msg(
            'Bank',
            'Your OTP is 1234',
            at(9),
            thread: 'sms:bank',
            addressed: null,
          ),
        ],
        noTurns,
        now,
      );
      expect(feed.needsYou, isEmpty);
    });
  });

  group('You said you’d', () {
    final priya = msg(
      'Priya',
      'Can you share the photos?',
      at(14),
      thread: 'wa:priya',
    );

    test('a promise with a time, said today', () {
      final feed = HomeFeed.summarise(
        [priya],
        turns({
          'wa:priya': [
            (at(14, 15), 'I’ll share the photos tonight'),
            (at(14, 16), 'haha yes'),
          ],
        }),
        now,
      );
      expect(feed.promises.single.turn.text, 'I’ll share the photos tonight');
      expect(feed.promises.single.to, 'Priya');
      expect(feed.promises.single.entry.sender, 'You');
    });

    test('not without a time, not from yesterday, not once handled', () {
      final said = turns({
        'wa:priya': [
          (at(14, 15), 'I will share them'),
          (DateTime(2026, 10, 2, 20), 'I’ll call you at 9'),
          (at(15), 'I’ll send it by 6'),
        ],
      });
      final handled = HomeFeed.summarise([priya], said, now).promises.single;
      expect(handled.turn.text, 'I’ll send it by 6');
      expect(
        HomeFeed.summarise([priya], said, now, skip: {handled.key}).promises,
        isEmpty,
      );
    });

    test('needs a message from that chat to say who it was to', () {
      final feed = HomeFeed.summarise(
        const [],
        turns({
          'wa:priya': [(at(14, 15), 'I’ll share the photos tonight')],
        }),
        now,
      );
      expect(feed.promises, isEmpty);
    });
  });

  group('Busy groups', () {
    test(
      'groups with five or more messages not for the owner, busiest first',
      () {
        final team = [
          for (var i = 0; i < 5; i++)
            msg(
              'Mahesh',
              'slot $i',
              at(10, i),
              thread: 'wa:bpa',
              title: 'Team BPA',
              group: true,
              addressed: Addressed.group,
            ),
        ];
        final feed = HomeFeed.summarise(
          [
            for (var i = 0; i < 7; i++) gang('Sneha', 'meme $i', at(15, i)),
            ...team,
            for (var i = 0; i < 4; i++)
              msg(
                'X',
                'hi',
                at(9, i),
                thread: 'wa:quiet',
                title: 'Quiet group',
                group: true,
                addressed: Addressed.group,
              ),
          ],
          noTurns,
          now,
        );
        expect(feed.busyGroups.map((g) => (g.name, g.count)), [
          ('College gang', 7),
          ('Team BPA', 5),
        ]);
        expect(feed.busyGroups.first.latest.content, 'meme 6');
      },
    );
  });

  group('group summaries', () {
    final at10 = at(10).millisecondsSinceEpoch;

    test('summed up again only once the group has moved on', () {
      expect(GroupSummaries.needsSummary(null, 6, now), isTrue);
      final kept = {'x': 'Friday is on', 'n': 6, 't': at10};
      // Nothing new, or a little new and recent: keep the line.
      expect(GroupSummaries.needsSummary(kept, 6, at(16)), isFalse);
      expect(GroupSummaries.needsSummary(kept, 8, at(10, 30)), isFalse);
      // Five more messages, or anything new after 45 minutes.
      expect(GroupSummaries.needsSummary(kept, 11, at(10, 30)), isTrue);
      expect(GroupSummaries.needsSummary(kept, 7, at(11)), isTrue);
      // A line from yesterday.
      expect(
        GroupSummaries.needsSummary(kept, 6, DateTime(2026, 10, 4, 9)),
        isTrue,
      );
    });

    test('reads the model’s lines, fenced or not', () {
      expect(
        GroupSummaries.parseReply(
          '```json\n{"College gang": " Friday at 7, Rahul drives ", "X": 3}\n```',
        ),
        {'College gang': 'Friday at 7, Rahul drives'},
      );
      expect(GroupSummaries.parseReply('not json'), isEmpty);
      expect(GroupSummaries.parseReply(null), isEmpty);
    });

    test('the prompt gives each group’s messages oldest first', () {
      final feed = HomeFeed.summarise(
        [for (var i = 0; i < 5; i++) gang('Sneha', 'line $i', at(15, i))],
        noTurns,
        now,
      );
      final prompt = GroupSummaries.prompt(feed.busyGroups);
      expect(prompt, startsWith('## College gang\nSneha: line 0'));
      expect(prompt, endsWith('Sneha: line 4'));
    });
  });
}
