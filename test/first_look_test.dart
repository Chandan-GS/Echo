import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/features/echo/data/context/chat_context_store.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/onboarding/data/first_look.dart';

// Thu 26 Nov 2026, early evening: onboarding after work.
final now = DateTime(2026, 11, 26, 18, 30);
DateTime ago(int minutes) => now.subtract(Duration(minutes: minutes));

RawData chat(
  String sender,
  String content,
  DateTime at, {
  String thread = 'wa:1',
  String addressed = 'direct',
  bool isGroup = false,
  String? threadTitle,
}) => RawData()
  ..source = 'Whatsapp'
  ..sender = sender
  ..content = content
  ..timestamp = at
  ..thread = thread
  ..addressed = addressed
  ..isGroup = isGroup
  ..threadTitle = threadTitle;

RawData note(String source, String sender, String content, DateTime at) =>
    RawData()
      ..source = source
      ..sender = sender
      ..content = content
      ..timestamp = at;

RawData event(String title, DateTime start, String times) => RawData()
  ..source = 'Calendar'
  ..sender = title
  ..content = times
  ..timestamp = start;

int sentences(String text) => RegExp(r'[.!?](\s|$)').allMatches(text).length;

void main() {
  group('first look', () {
    test('a quiet phone says what tomorrow’s briefing will do', () {
      final look = buildFirstLook(entries: const [], now: now);
      expect(look.kind, FirstLookKind.empty);
      expect(look.notifications, 0);
      expect(look.text, startsWith('Hi, your phone is nice and quiet'));
      expect(look.text, contains('Tomorrow at 7 AM'));
      expect(look.text, contains('who’s waiting on you'));
      expect(sentences(look.text), 3);
    });

    test('only offers and codes count as nothing to read', () {
      final look = buildFirstLook(
        entries: [
          note('Swiggy', 'Swiggy', 'Flat 50% off tonight', ago(30)),
          note('Messages', 'AX-HDFC', 'Your OTP is 123456', ago(10)),
        ],
        now: now,
        name: 'Chandan Gowda',
      );
      expect(look.kind, FirstLookKind.empty);
      expect(look.text, startsWith('Hi Chandan, your phone only has offers'));
    });

    test('a normal phone: counts, who’s waiting and what’s coming up', () {
      final look = buildFirstLook(
        entries: [
          chat('Rahul', 'Are we still on?', ago(40), thread: 'wa:rahul'),
          chat('Priya', 'Sent you the deck', ago(20), thread: 'wa:priya'),
          // Answered since: not waiting.
          chat('Mom', 'Call me back', ago(90), thread: 'wa:mom'),
          // Group chatter isn't waiting on the owner.
          chat(
            'Arjun',
            'lol',
            ago(5),
            thread: 'wa:gang',
            addressed: 'group',
            isGroup: true,
            threadTitle: 'College gang',
          ),
          note('Gmail', 'Amit', 'Invoice for November', ago(60)),
          note('Swiggy', 'Swiggy', 'Flat 50% off tonight', ago(30)),
          event('Standup', DateTime(2026, 11, 27, 10), '10:00 AM - 10:15 AM'),
        ],
        now: now,
        myTurns: MyTurns({
          'wa:mom': [MyTurn(ago(60), 'Calling now')],
        }),
      );
      expect(look.kind, FirstLookKind.normal);
      expect(look.notifications, 5);
      expect(look.apps, 2);
      expect(look.waiting, ['Priya', 'Rahul']);
      expect(look.comingUp, 1);
      expect(
        look.text,
        'Hi, here’s a first look at what’s on your phone. '
        'There are 5 notifications from 2 apps, and I’ve set aside 1 offer '
        'or code. Priya and Rahul are waiting to hear back from you. '
        'Coming up: Standup, tomorrow at 10 AM. '
        'Tomorrow at 7 AM, I’ll read you all of it like this, so you never '
        'have to scroll.',
      );
    });

    test('a busy phone stays at five sentences and names two people', () {
      final entries = [
        for (var i = 0; i < 40; i++)
          chat('Person $i', 'Message $i', ago(i + 1), thread: 'wa:$i'),
        chat('Boss', 'Quick sync today at 8 PM', ago(50), thread: 'wa:boss'),
      ];
      final look = buildFirstLook(
        entries: entries,
        now: now,
        briefingTime: '06:45',
      );
      expect(look.kind, FirstLookKind.busy);
      expect(look.notifications, 41);
      expect(
        look.text,
        contains('It’s a busy one: 41 notifications from Whatsapp.'),
      );
      expect(
        look.text,
        contains('Person 0, Person 1 and 39 others are waiting'),
      );
      expect(
        look.text,
        contains('Coming up: a message from Boss, today at 8 PM.'),
      );
      expect(look.text, contains('Tomorrow at 6:45 AM'));
      expect(sentences(look.text), 5);
    });

    test('a briefing time still ahead today is said as today', () {
      final early = DateTime(2026, 11, 26, 5, 30);
      final look = buildFirstLook(entries: const [], now: early);
      expect(look.text, contains('Today at 7 AM'));
    });

    test('a day-old notification and a hidden app are left out', () {
      final look = buildFirstLook(
        entries: [
          note(
            'Gmail',
            'Amit',
            'Old news',
            now.subtract(const Duration(days: 2)),
          ),
          note('Slack', 'Team', 'Deploy done', ago(5)),
        ],
        now: now,
        excluded: {'Slack'},
      );
      expect(look.kind, FirstLookKind.empty);
    });

    test('says times the way Echo speaks them', () {
      expect(spokenClock(DateTime(2026, 1, 1, 7)), '7 AM');
      expect(spokenClock(DateTime(2026, 1, 1, 17, 30)), '5:30 PM');
      expect(spokenClock(DateTime(2026, 1, 1, 0, 5)), '12:05 AM');
    });
  });
}
