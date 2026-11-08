import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/features/echo/data/wrap/evening_wrap.dart';
import 'package:project_echo/features/echo/presentation/widgets/briefing_controls.dart';

void main() {
  group('buildEveningWrap', () {
    test('two people waiting are both named, the longest first', () {
      final wrap = buildEveningWrap(
        const WrapInput(waiting: [WrapWaiting('Rohan', 1), WrapWaiting('Amma', 2)]),
      );
      expect(
        wrap.rawText,
        contains(
          'Two people are still waiting: **Amma** for two days, and **Rohan** since yesterday.',
        ),
      );
    });

    test('one person, waiting since today', () {
      final wrap = buildEveningWrap(
        const WrapInput(waiting: [WrapWaiting('Neha', 0)]),
      );
      expect(wrap.rawText, contains('**Neha** has been waiting since today.'));
    });

    test('a crowd names only the longest waiter', () {
      final wrap = buildEveningWrap(
        const WrapInput(
          waiting: [
            WrapWaiting('A', 0),
            WrapWaiting('B', 3),
            WrapWaiting('C', 1),
            WrapWaiting('D', 1),
            WrapWaiting('E', 1),
          ],
        ),
      );
      expect(wrap.rawText, contains('Five people are still waiting.'));
      expect(wrap.rawText, contains('**B** has waited longest, for three days.'));
    });

    test('to-dos: some done', () {
      final wrap = buildEveningWrap(
        const WrapInput(
          doneToday: 3,
          totalToday: 4,
          openToday: ['Send Karan the deck'],
        ),
      );
      expect(
        wrap.rawText,
        contains('You finished three of four to-dos today. Still open: Send Karan the deck.'),
      );
    });

    test('to-dos: all done, none done', () {
      expect(
        buildEveningWrap(
          const WrapInput(doneToday: 2, totalToday: 2),
        ).rawText,
        contains('You finished all two to-dos today.'),
      );
      expect(
        buildEveningWrap(
          const WrapInput(totalToday: 2, openToday: ['A', 'B']),
        ).rawText,
        contains('Two to-dos are still open today, starting with A.'),
      );
    });

    test('tomorrow: with a time, and without', () {
      expect(
        buildEveningWrap(
          const WrapInput(
            waiting: [WrapWaiting('A', 1)],
            tomorrowFirst: 'Design review',
            tomorrowTime: '10:40 AM',
            tomorrowCount: 1,
          ),
        ).rawText,
        contains('Tomorrow starts with Design review at 10:40 AM.'),
      );
      expect(
        buildEveningWrap(
          const WrapInput(
            waiting: [WrapWaiting('A', 1)],
            tomorrowFirst: 'Pay the bill',
            tomorrowCount: 3,
          ),
        ).rawText,
        contains('Tomorrow: Pay the bill, and two more.'),
      );
    });

    test('someone who owes an answer is named', () {
      final wrap = buildEveningWrap(
        const WrapInput(owed: [WrapOwed('Karan', 'the invoice', 3)]),
      );
      expect(wrap.rawText, contains('**Karan** still owes you an answer about the invoice.'));
      expect(wrap.clear, isFalse);
    });

    test('a clear day says so plainly', () {
      final wrap = buildEveningWrap(const WrapInput());
      expect(wrap.clear, isTrue);
      expect(wrap.noData, isFalse);
      expect(wrap.rawText, contains("Nobody's waiting on you"));
    });

    test('an empty app does not pretend it was a clear day', () {
      final wrap = buildEveningWrap(const WrapInput(hasAnyData: false));
      expect(wrap.noData, isTrue);
      expect(wrap.rawText, contains("hasn't heard any of your messages"));
    });

    test('never says promise', () {
      final wrap = buildEveningWrap(
        const WrapInput(
          waiting: [WrapWaiting('A', 1)],
          totalToday: 2,
          openToday: ['B'],
          doneToday: 1,
          owed: [WrapOwed('C', 'the thing', 2)],
        ),
      );
      expect(wrap.rawText.toLowerCase(), isNot(contains('promise')));
    });

    test('stars in a name cannot break the markup', () {
      final wrap = buildEveningWrap(
        const WrapInput(waiting: [WrapWaiting('*Ani*', 1)]),
      );
      expect(wrap.rawText, contains('**Ani** has been waiting'));
    });
  });

  group('owedFromTurns', () {
    final now = DateTime(2026, 11, 8, 21, 30);
    ({String thread, DateTime at, String text}) turn(
      String thread,
      DateTime at,
      String text,
    ) => (thread: thread, at: at, text: text);

    test('an unanswered ask from days ago counts', () {
      final owed = owedFromTurns(
        turns: [turn('t1', DateTime(2026, 11, 5, 10), 'Can you approve the invoice?')],
        threads: {
          't1': (name: 'Karan', lastHeard: DateTime(2026, 11, 4, 10), isGroup: false),
        },
        asksSomething: (_) => true,
        now: now,
      );
      expect(owed.single.name, 'Karan');
      expect(owed.single.days, 3);
      expect(owed.single.what, 'Can you approve the invoice');
    });

    test('a reply since then does not', () {
      final owed = owedFromTurns(
        turns: [turn('t1', DateTime(2026, 11, 5), 'Can you check?')],
        threads: {
          't1': (name: 'Karan', lastHeard: DateTime(2026, 11, 6), isGroup: false),
        },
        asksSomething: (_) => true,
        now: now,
      );
      expect(owed, isEmpty);
    });

    test('groups, today, and statements are ignored', () {
      final threads = {
        'g': (name: 'Gang', lastHeard: DateTime(2026, 11, 1), isGroup: true),
        'p': (name: 'P', lastHeard: DateTime(2026, 11, 1), isGroup: false),
      };
      expect(
        owedFromTurns(
          turns: [turn('g', DateTime(2026, 11, 5), 'Anyone?')],
          threads: threads,
          asksSomething: (_) => true,
          now: now,
        ),
        isEmpty,
      );
      expect(
        owedFromTurns(
          turns: [turn('p', DateTime(2026, 11, 8, 9), 'Can you?')],
          threads: threads,
          asksSomething: (_) => true,
          now: now,
        ),
        isEmpty,
      );
      expect(
        owedFromTurns(
          turns: [turn('p', DateTime(2026, 11, 5), 'Sounds good')],
          threads: threads,
          asksSomething: (_) => false,
          now: now,
        ),
        isEmpty,
      );
    });

    test('a thread Echo no longer knows (excluded app) is skipped', () {
      expect(
        owedFromTurns(
          turns: [turn('gone', DateTime(2026, 11, 5), 'Can you?')],
          threads: const {},
          asksSomething: (_) => true,
          now: now,
        ),
        isEmpty,
      );
    });
  });

  group('transcript sentences', () {
    test('sentences keep the spacing between them', () {
      final s = transcriptSentences('First one. Second **Neha** here.\nThird.');
      expect(s, ['First one.', ' Second **Neha** here.', '\nThird.']);
      expect(s.join(), 'First one. Second **Neha** here.\nThird.');
    });

    test('the voice is matched in reading order, ignoring markup', () {
      final s = transcriptSentences('Hello there. **Amma** is waiting. Bye.');
      expect(matchSpokenSentence(s, 'Amma is waiting.', from: 0), 1);
      expect(matchSpokenSentence(s, 'Bye.', from: 1), 2);
    });

    test('a repeat matches the later sentence once reading has moved on', () {
      final s = transcriptSentences('Okay. Done. Okay.');
      expect(matchSpokenSentence(s, 'Okay.', from: 1), 2);
    });

    test('nothing matching stays where it was', () {
      final s = transcriptSentences('One. Two.');
      expect(matchSpokenSentence(s, 'Three.', from: 1), 1);
    });
  });
}
