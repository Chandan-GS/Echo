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
}
