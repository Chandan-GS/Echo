import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/features/echo/data/datasources/briefing_prompt.dart';

void main() {
  group('Briefing Prompt Filters', () {
    test('stripFillerCommentary removes robotic filler comments', () {
      const input =
          'Good morning, sir. The DevOps Bot has shared a positive update: our production deployment was successful, with zero errors. That’s a great start. '
          'Your account ending in 1234 was credited with \$500.00. That’s a relief. '
          'Mike has requested a push to **3 PM**, as he’s running late. That’s a good scheduling request. '
          'The Daily Standup is at **10:00 AM**, which is a key point to note. '
          'Priya has sent a subject for the Q3 Design Assets Review, attaching the figma links. That’s a useful piece of information. '
          'John has requested confirmation of the liability cap before sending the contract. Important to include. '
          'Swiggy has sent an SMS with an order out for delivery and an OTP of 1234. That’s another useful detail. '
          'The Dentist appointment is at **4:30 PM** tomorrow. That’s a specific time to note.';

      final cleaned = stripFillerCommentary(input);

      expect(cleaned, isNot(contains('That’s a great start')));
      expect(cleaned, isNot(contains('That’s a relief')));
      expect(cleaned, isNot(contains('That’s a good scheduling request')));
      expect(cleaned, isNot(contains('which is a key point to note')));
      expect(cleaned, isNot(contains('That’s a useful piece of information')));
      expect(cleaned, isNot(contains('Important to include')));
      expect(cleaned, isNot(contains('That’s another useful detail')));
      expect(cleaned, isNot(contains('That’s a specific time to note')));

      expect(
        cleaned,
        equals(
          'Good morning, sir. The DevOps Bot has shared a positive update: our production deployment was successful, with zero errors. '
          'Your account ending in 1234 was credited with \$500.00. '
          'Mike has requested a push to **3 PM**, as he’s running late. '
          'The Daily Standup is at **10:00 AM**. '
          'Priya has sent a subject for the Q3 Design Assets Review, attaching the figma links. '
          'John has requested confirmation of the liability cap before sending the contract. '
          'Swiggy has sent an SMS with an order out for delivery and an OTP of 1234. '
          'The Dentist appointment is at **4:30 PM** tomorrow.',
        ),
      );
    });

    test('autoBold wraps key entities in ** double asterisks if missing', () {
      const input = 'Mike is late for the meeting at 3 PM on Friday. John is already there.';
      final bolded = autoBold(input);

      expect(bolded, equals('**Mike** is late for the meeting at **3 PM** on **Friday**. **John** is already there.'));
    });

    test('autoBold does not double bold existing ** markers', () {
      const input = '**Mike** is late for the meeting at **3 PM** on Friday.';
      final bolded = autoBold(input);

      expect(bolded, equals('**Mike** is late for the meeting at **3 PM** on **Friday**.'));
    });
  });

  group('getBriefingSystemInstruction tone', () {
    test('uses the default warm tone when none is provided', () {
      final instr = getBriefingSystemInstruction('Ada');
      expect(instr, contains('professional yet warm tone'));
    });

    test('injects a custom tone instruction when provided', () {
      final instr = getBriefingSystemInstruction(
        'Ada',
        toneInstruction: 'Be extremely concise and direct.',
      );
      expect(instr, contains('Be extremely concise and direct.'));
      expect(instr, isNot(contains('professional yet warm tone')));
    });

    test('buildQwenPrompt threads the tone through', () {
      final prompt = buildQwenPrompt(
        'Meeting at 3 PM',
        'Ada',
        toneInstruction: 'Speak like a friendly companion.',
      );
      expect(prompt, contains('Speak like a friendly companion.'));
      expect(prompt, contains('<|im_start|>system'));
    });
  });

  group('deduplicateSentences', () {
    test('collapses two identical sentences into one', () {
      const input =
          'The deployment succeeded without errors. The deployment succeeded without errors.';
      expect(
        deduplicateSentences(input),
        equals('The deployment succeeded without errors.'),
      );
    });

    test('keeps distinct sentences', () {
      const input = 'Meeting scheduled at noon. Dentist appointment tomorrow afternoon.';
      expect(
        deduplicateSentences(input),
        equals('Meeting scheduled at noon. Dentist appointment tomorrow afternoon.'),
      );
    });

    test('removes near-duplicates above the overlap threshold', () {
      const input =
          'Mike requested to push the meeting to 3 PM. Mike requested to push the meeting to 3 PM because he is late.';
      final result = deduplicateSentences(input);
      // Only the first (earliest) variant survives.
      expect(result, equals('Mike requested to push the meeting to 3 PM.'));
    });

    test('handles empty input gracefully', () {
      expect(deduplicateSentences(''), equals(''));
      expect(deduplicateSentences('   '), equals(''));
    });

    test('keeps short-word-only sentences (no false dedup)', () {
      const input = 'See you at 3 PM. Call me now.';
      expect(deduplicateSentences(input), equals('See you at 3 PM. Call me now.'));
    });
  });

  group('stripForTts', () {
    test('removes bold markers', () {
      expect(stripForTts('**Good morning**, sir.'), equals('Good morning, sir.'));
    });

    test('removes leading numbered list markers', () {
      expect(stripForTts('1. Buy milk'), equals('Buy milk'));
      expect(stripForTts('2) Call John'), equals('Call John'));
    });

    test('removes leading bullet markers', () {
      expect(stripForTts('- Take out trash'), equals('Take out trash'));
      expect(stripForTts('• Feed the cat'), equals('Feed the cat'));
    });
  });

  group('stripSignOff', () {
    test('truncates from a sign-off line onward', () {
      const input = 'Here is your briefing.\nBest regards,\nEcho';
      expect(stripSignOff(input), equals('Here is your briefing.'));
    });

    test('leaves text without a sign-off unchanged', () {
      const input = 'You have a meeting at 3 PM today.';
      expect(stripSignOff(input), equals('You have a meeting at 3 PM today.'));
    });
  });
}
