import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/features/echo/data/context/addressed.dart';
import 'package:project_echo/features/echo/data/context/chat_context_store.dart';
import 'package:project_echo/features/echo/data/datasources/briefing_prompt.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/relevance/briefing_selection.dart';

// Sat 26 Sep 2026.
DateTime at(int hour, [int minute = 0]) => DateTime(2026, 9, 26, hour, minute);

RawData chat(
  String sender,
  String content,
  DateTime when, {
  String thread = 'com.whatsapp:aa11',
  String? title = 'College gang',
  bool group = true,
  Addressed? addressed,
}) =>
    RawData()
      ..source = 'Whatsapp'
      ..sender = sender
      ..content = content
      ..timestamp = when
      ..thread = thread
      ..threadTitle = title
      ..isGroup = group
      ..addressed = addressed?.name;

void main() {
  const me = {'Chandan G S', 'Chandan'};

  group('who a message is for', () {
    Addressed classify(
      String text, {
      bool group = true,
      DateTime? spoke,
      int since = 0,
      DateTime? when,
    }) =>
        addressedFor(
          isGroup: group,
          content: text,
          at: when ?? at(18),
          myNames: me,
          mySpokeAt: spoke,
          messagesSince: since,
        );

    test('a one-to-one chat is always for you', () {
      expect(classify('lunch?', group: false), Addressed.direct);
    });

    test('a group message naming you is a mention, @ or not, any case', () {
      expect(classify('@Chandan are you coming'), Addressed.mentioned);
      expect(classify('chandan, you in?'), Addressed.mentioned);
    });

    test('a longer name that starts with yours is not a mention', () {
      expect(classify('Chandana is coming too'), Addressed.group);
    });

    test('names shorter than three letters never match', () {
      expect(mentionsAny('go to the gym', {'Go'}), isFalse);
    });

    test('right after you spoke, a group message reads as a reply', () {
      expect(classify('yes I can', spoke: at(17, 50), since: 2), Addressed.reply);
    });

    test('too long after, or too many messages between, is just chatter', () {
      expect(classify('yes I can', spoke: at(17, 20)), Addressed.group);
      expect(classify('yes I can', spoke: at(17, 55), since: 5), Addressed.group);
    });

    test('a message from before you spoke is not a reply to you', () {
      expect(classify('hm', spoke: at(18, 5), when: at(18)), Addressed.group);
    });

    test('owner names: full name, first name and app names, never "You"', () {
      expect(
        ownerNames('Chandan G S', ['You', 'CGS']),
        {'Chandan G S', 'Chandan', 'CGS'},
      );
      expect(ownerNames(null, const []), isEmpty);
    });
  });

  group('taps and swipes', () {
    test('no record is neutral', () {
      expect(Engagement.none.affinity('com.whatsapp:aa11'), 0);
      expect(Engagement.none.affinity(null), 0);
    });

    test('a thread you open leans positive, one you swipe leans negative', () {
      const e = Engagement({
        'com.whatsapp:fam': (6.0, 0.0),
        'com.whatsapp:spam': (0.0, 6.0),
      });
      expect(e.affinity('com.whatsapp:fam'), greaterThan(0.4));
      expect(e.affinity('com.whatsapp:spam'), lessThan(-0.4));
    });

    test('a new chat starts from how you treat that app', () {
      const e = Engagement({'com.slack:a': (8.0, 0.0), 'com.slack:b': (6.0, 1.0)});
      final fresh = e.affinity('com.slack:new');
      expect(fresh, greaterThan(0));
      expect(fresh, lessThan(e.affinity('com.slack:a')));
    });

    test('one tap does not make a favourite', () {
      const e = Engagement({'com.whatsapp:x': (1.0, 0.0)});
      expect(e.affinity('com.whatsapp:x'), lessThan(0.3));
    });
  });

  group('your own messages', () {
    final turns = MyTurns({
      'com.whatsapp:aa11': [
        MyTurn(at(17), 'who is driving?'),
        MyTurn(at(18, 30), 'never mind'),
      ],
    });

    test('the latest one at or before a moment', () {
      expect(turns.lastBefore('com.whatsapp:aa11', at(18))?.text, 'who is driving?');
      expect(turns.lastBefore('com.whatsapp:aa11', at(19))?.text, 'never mind');
      expect(turns.lastBefore('com.whatsapp:aa11', at(16)), isNull);
      expect(turns.lastBefore('com.whatsapp:other', at(19)), isNull);
      expect(turns.lastBefore(null, at(19)), isNull);
    });
  });

  group('briefing selection', () {
    test('a busy group only gets its latest few messages of chatter in', () {
      final chatter = [
        for (var i = 0; i < 8; i++)
          chat('Friend $i', 'party plan tonight at 9 PM, idea $i', at(10, i),
              addressed: Addressed.group),
      ];
      final picked = selectForBriefing(chatter, at(12), limit: 25);
      expect(picked, hasLength(groupChatterPerThread));
      expect(picked.map((i) => i.entry.sender),
          containsAll(['Friend 7', 'Friend 6', 'Friend 5']));
    });

    test('a message for you beats group chatter when there is no room', () {
      final chatter = [
        for (var i = 0; i < 3; i++)
          chat('Friend $i', 'random chatter number $i', at(10, i),
              thread: 'com.whatsapp:g$i', addressed: Addressed.group),
      ];
      final mention = chat('Rahul', '@Chandan can you bring the adapter',
          at(9), thread: 'com.whatsapp:g9', addressed: Addressed.mentioned);
      final picked = selectForBriefing([...chatter, mention], at(12), limit: 1);
      expect(picked.single.entry.sender, 'Rahul');
    });

    test('a thread you always swipe away drops behind one you open', () {
      final a = chat('Ad bot', 'new offers in store', at(10),
          thread: 'com.x:ads', group: false, addressed: Addressed.direct);
      final b = chat('Mom', 'call me when you can', at(10),
          thread: 'com.x:mom', group: false, addressed: Addressed.direct);
      const e = Engagement({'com.x:ads': (0.0, 10.0), 'com.x:mom': (10.0, 0.0)});
      final picked = selectForBriefing([a, b], at(12), affinity: e.affinity, limit: 1);
      expect(picked.single.entry.sender, 'Mom');
    });
  });

  group('prompt lines', () {
    test('a group mention names the group and says it mentions you', () {
      final e = chat('Rahul', 'bring it', at(18), addressed: Addressed.mentioned);
      expect(
        formatEntry(e, content: e.content, when: 'Today, 6:00 PM'),
        '[Today, 6:00 PM] Rahul in "College gang" (Whatsapp group, mentions you): bring it',
      );
    });

    test('a reply quotes what you wrote', () {
      final e = chat('Rahul', 'I can', at(18), addressed: Addressed.reply);
      final turns = MyTurns({
        'com.whatsapp:aa11': [MyTurn(at(17, 55), 'who is driving?')],
      });
      expect(
        formatEntry(e, content: e.content, myTurns: turns),
        'Rahul in "College gang" (Whatsapp group, replying to you, after you wrote "who is driving?"): I can',
      );
    });

    test('a direct message is "to you"; other notifications stay as they were', () {
      final dm = chat('Mom', 'call me', at(18),
          title: 'Mom', group: false, addressed: Addressed.direct);
      expect(formatEntry(dm, content: dm.content), 'Mom (Whatsapp, to you): call me');
      final mail = RawData()
        ..source = 'Gmail'
        ..sender = 'Bank'
        ..content = 'Statement ready'
        ..timestamp = at(9);
      expect(formatEntry(mail, content: mail.content), 'Bank (Gmail): Statement ready');
    });

    test('the sender as shown: "Rahul · College gang" for a group', () {
      expect(chat('Rahul', 'x', at(9)).who, 'Rahul · College gang');
      expect(chat('Mom', 'x', at(9), title: 'Mom', group: false).who, 'Mom');
    });
  });
}
