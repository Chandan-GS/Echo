import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/core/services/reminders.dart';
import 'package:project_echo/features/echo/data/ask/ask_intents.dart';
import 'package:project_echo/features/echo/data/ask/citations.dart';
import 'package:project_echo/features/echo/data/ask/for_you.dart';
import 'package:project_echo/features/echo/data/context/addressed.dart';
import 'package:project_echo/features/echo/data/context/chat_context_store.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/reply/reply_drafter.dart';
import 'package:project_echo/features/echo/data/reply/reply_sender.dart';
import 'package:project_echo/features/echo/presentation/cubit/ask_ai_cubit.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/answer_text.dart';
import 'package:project_echo/features/todo/data/todo_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Sat 26 Sep 2026.
DateTime at(int hour, [int minute = 0]) => DateTime(2026, 9, 26, hour, minute);

RawData chat(
  String sender,
  String content,
  DateTime when, {
  String thread = 'com.whatsapp:aa11',
  String? title = 'College gang',
  bool group = true,
  Addressed? addressed = Addressed.group,
}) => RawData()
  ..source = 'Whatsapp'
  ..sender = sender
  ..content = content
  ..timestamp = when
  ..thread = thread
  ..threadTitle = title
  ..isGroup = group
  ..addressed = addressed?.name;

void main() {
  final rahul = chat(
    'Rahul',
    'Bring the HDMI adapter?',
    at(18),
    addressed: Addressed.mentioned,
  );
  final neha = chat(
    'Neha',
    'Deck by 4?',
    at(17),
    thread: 'com.Slack:nn',
    title: 'Neha',
    group: false,
    addressed: Addressed.direct,
  );
  final chats = replyCandidates([neha, rahul]);

  group('things to do, not questions', () {
    test('"reply to Rahul that …" drafts a reply with his words', () {
      final r = parseIntent("reply to rahul that i'll bring it", chats).reply!;
      expect(r.to, rahul);
      expect(r.gist, "i'll bring it");
    });

    test('"tell Neha I\'m running late" and "let Neha know …"', () {
      expect(
        parseIntent("tell Neha I'm running late", chats).reply?.gist,
        "I'm running late",
      );
      expect(
        parseIntent('let neha know that I sent it', chats).reply?.gist,
        'I sent it',
      );
    });

    test('"draft a reply to Rahul" asks for a suggestion', () {
      final r = parseIntent('Draft a reply to Rahul', chats).reply!;
      expect(r.to, rahul);
      expect(r.gist, isNull);
    });

    test('a question about someone is still a question', () {
      expect(parseIntent('tell me what Rahul said', chats).reply, isNull);
      expect(parseIntent('what did Neha message me?', chats).reply, isNull);
      expect(
        parseIntent('reply to Priya', chats).reply,
        isNull,
      ); // no such chat
    });

    test('"add them to my list", and both at once', () {
      expect(parseIntent('add them to my list', chats).addToList, isTrue);
      expect(parseIntent('put that on my to-do', chats).addToList, isTrue);
      final both = parseIntent("add them, and tell Rahul I'll bring it", chats);
      expect(both.addToList, isTrue);
      expect(both.reply?.gist, "I'll bring it");
      expect(
        parseIntent('what should I add to the deck?', chats).isEmpty,
        isTrue,
      );
    });

    test('chats meant for the owner come first', () {
      final chatter = chat('Friend', 'lol', at(19));
      expect(replyCandidates([chatter, neha, rahul]), [rahul, neha, chatter]);
    });
  });

  group('citations', () {
    const answer =
        'Neha needs the deck by **4 PM** [1], and Rahul asked about the adapter [2, 3]. Ignore [9].';

    test('numbers in order of first mention, only real ones', () {
      expect(citedNumbers(answer, 3), [1, 2, 3]);
      expect(citedNumbers(answer, 2), [1, 2]);
    });

    test('said aloud without marks', () {
      expect(
        plainAnswer(answer),
        'Neha needs the deck by 4 PM, and Rahul asked about the adapter. Ignore.',
      );
    });

    test('pieces: words, bold, and citation dots', () {
      final pieces = answerPieces('By **4 PM** [1].', 1);
      expect(pieces.whereType<CitePiece>().single.numbers, [1]);
      final bold = pieces.whereType<WordPiece>().where((w) => w.bold);
      expect(bold.map((w) => w.text.trim()), ['4', 'PM']);
      expect(
        pieces.whereType<WordPiece>().any((w) => w.text.contains('*')),
        isFalse,
      );
    });
  });

  group('what Ask Echo opens with', () {
    test('the latest per chat that wants the owner, and the chatter', () {
      final since = at(14);
      final forYou = ForYou.summarise([
        neha,
        rahul,
        chat('Rahul', 'earlier one', at(16), addressed: Addressed.reply),
        chat('A', 'lol', at(15)),
        chat('B', 'haha', at(15, 30)),
        chat(
          'C',
          'old news',
          at(9),
          addressed: Addressed.direct,
          thread: 'x:c',
        ),
      ], since);
      expect(forYou.items, [rahul, neha]);
      expect(forYou.chats, 2);
      expect(forYou.chatter, 2);
      expect(forYou.busiestGroup, 'College gang');
    });

    test('nothing new is empty', () {
      expect(ForYou.summarise([neha], at(20)).isEmpty, isTrue);
    });
  });

  group('replies', () {
    test('the app comes from the chat id', () {
      expect(packageOfThread('com.whatsapp:1f3a'), 'com.whatsapp');
      expect(packageOfThread(null), isNull);
      expect(isWhatsApp('com.whatsapp.w4b'), isTrue);
    });

    test('without a model, the owner\'s own words, tidied', () {
      expect(
        localDraft(ReplyRequest(rahul, "i'll bring it, i promise")),
        "I'll bring it, I promise",
      );
      expect(localDraft(ReplyRequest(rahul, null)), '');
    });

    test("a model's quotes and labels are removed", () {
      expect(cleanDraft('"Yes, I\'ll bring it"'), "Yes, I'll bring it");
      expect(cleanDraft('Reply: On my way'), 'On my way');
    });

    test('the prompt has the message, the group and what the owner said', () {
      final prompt = draftPrompt(
        ReplyRequest(rahul, "I'll bring it"),
        MyTurns({
          'com.whatsapp:aa11': [MyTurn(at(17, 50), 'who has an adapter?')],
        }),
      );
      expect(prompt, contains('Rahul in the group "College gang"'));
      expect(
        prompt,
        contains('Earlier, the user wrote: "who has an adapter?"'),
      );
      expect(prompt, endsWith("What the user wants to say: I'll bring it"));
    });
  });

  test('what Echo says after adding', () {
    TodoItem on(DateTime day) => TodoItem(
      id: 1,
      title: 't',
      day: day,
      time: null,
      sort: 0,
      sender: '',
      app: '',
      sourceText: '',
      sourceKey: '',
      created: at(9),
    );
    final now = at(20);
    expect(
      addedLine([on(DateTime(2026, 9, 27))], now),
      "Done. It's on tomorrow's list.",
    );
    expect(
      addedLine([on(DateTime(2026, 9, 26)), on(DateTime(2026, 9, 26))], now),
      "Done. They're on today's list.",
    );
    expect(addedLine(const [], now), "There's nothing new to add from those.");
  });

  test('a chat read in its own app counts half a tap', () async {
    SharedPreferences.setMockInitialValues({});
    await ChatContextStore.recordEngagement('com.whatsapp:a', 'read', at(9));
    await ChatContextStore.recordEngagement('com.whatsapp:a', 'read', at(10));
    await ChatContextStore.recordEngagement('com.whatsapp:b', 'opened', at(10));
    final e = await ChatContextStore.loadEngagement();
    expect(e.counts['com.whatsapp:a'], (1.0, 0.0));
    expect(e.counts['com.whatsapp:b'], (1.0, 0.0));
  });

  group('to-dos in answers', () {
    test('the tag says how many, and is never shown or spoken', () {
      const answer =
          'Send the deck by **4 PM** [1] and call Rahul [2]. [todo:2]';
      expect(todoCount(answer), 2);
      expect(todoCount('Nothing to do here.'), 0);
      expect(plainAnswer(answer), 'Send the deck by 4 PM and call Rahul.');
      expect(withoutTodoTag(answer), endsWith('call Rahul [2].'));
    });

    test('a tag still streaming in is hidden too', () {
      expect(withoutTodoTag('Call Rahul. [to'), 'Call Rahul.');
      expect(withoutTodoTag('Call Rahul. [todo:'), 'Call Rahul.');
    });

    test('which list things went on', () {
      TodoItem on(DateTime day) => TodoItem(
        id: 1,
        title: 't',
        day: day,
        time: null,
        sort: 0,
        sender: '',
        app: '',
        sourceText: '',
        sourceKey: '',
        created: at(9),
      );
      expect(addedTo([on(DateTime(2026, 9, 27))], at(20)), 'tomorrow');
      expect(
        addedTo([on(DateTime(2026, 9, 26)), on(DateTime(2026, 9, 27))], at(20)),
        'your list',
      );
    });
  });

  group('For you card buttons', () {
    test(
      '"Add to my list" only for messages that ask something or name a time',
      () {
        expect(
          looksActionable(chat('Rahul', 'Can you bring the adapter?', at(9))),
          isTrue,
        );
        expect(
          looksActionable(chat('Mom', 'Call me when you are free', at(9))),
          isTrue,
        );
        expect(
          looksActionable(chat('A', 'Dinner at 8 tonight', at(9))),
          isTrue,
        );
        expect(looksActionable(chat('B', 'lol nice', at(9))), isFalse);
      },
    );

    test(
      '"Remind me" 20 minutes before the time named, when there is time',
      () {
        final rahul = chat('Rahul', 'Need to know by 8 tonight', at(14));
        expect(reminderTimeFor(rahul, at(15)), DateTime(2026, 9, 26, 19, 40));
        expect(reminderTimeFor(rahul, at(19, 50)), isNull); // too late
        expect(reminderTimeFor(chat('B', 'lol', at(9)), at(10)), isNull);
      },
    );
  });
}
