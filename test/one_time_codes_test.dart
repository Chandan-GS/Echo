import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/core/services/one_time_codes.dart';

void main() {
  group('masks codes', () {
    const leaks = {
      'Your login code is 482913': '482913',
      '482913 is your Instagram code': '482913',
      'G-482913 is your Google verification code.': 'G-482913',
      'Your WhatsApp code: 482-913': '482-913',
      'Telegram code 48291. Do not give it to anyone. Your code': '48291',
      'OTP:482913': '482913',
      'OTP-482913': '482913',
      'Your OTP:\n482913': '482913',
      'Use A1B2C3 as your verification code': 'A1B2C3',
      'otp hai 4829 bata do': '4829',
      'आपका ओटीपी 482913 है': '482913',
      'Your code is 4 8 2 9 1 3': '4 8 2 9 1 3',
      'Door pin: 2580': '2580',
      '482913 is the OTP for txn of INR 500 at AMAZON on HDFC card ending. '
              'Valid for 10 mins.':
          '482913',
    };
    leaks.forEach((message, code) {
      test(message, () {
        final out = withoutOneTimeCodes(message);
        expect(out, isNot(contains(code)));
        expect(out, contains(oneTimeCodeMask));
      });
    });
  });

  test('keeps the amount in a bank text', () {
    final out = withoutOneTimeCodes('OTP for Rs. 5000 at Amazon is 482913');
    expect(out, contains('Rs. 5000'));
    expect(out, isNot(contains('482913')));
  });

  group('leaves ordinary messages alone', () {
    const safe = [
      'Meet at 1930 near gate 4',
      'The flat is 2400 a month',
      'Your Zomato order 4829 is on the way',
      'can you pin this message 1234 times',
      'we shipped the code review, PR 1234 is merged',
      'Call me on 9876543210',
      'Invoice 482913 is attached',
    ];
    for (final message in safe) {
      test(message, () => expect(withoutOneTimeCodes(message), message));
    }
  });

  test('dates, times and phone numbers survive next to a cue', () {
    const line = '2026-11-08 10:30 your code was sent to 9876543210';
    expect(withoutOneTimeCodes(line), line);
  });

  test('only numbers near the cue are masked', () {
    final far = 'x' * 200;
    final out = withoutOneTimeCodes('Your OTP is 482913 $far room 4242');
    expect(out, contains('room 4242'));
    expect(out, isNot(contains('482913')));
  });

  test('empty text', () => expect(withoutOneTimeCodes(''), ''));
}
