import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/features/echo/data/relevance/temporal_relevance.dart';

// Sat 26 Sep 2026.
DateTime at(int day, int hour, [int minute = 0, int month = 9]) =>
    DateTime(2026, month, day, hour, minute);

RelevanceWindow only(String text, DateTime receivedAt) {
  final windows = relevanceWindows(text, receivedAt);
  expect(windows, hasLength(1), reason: '$windows');
  return windows.single;
}

void main() {
  group('relative days resolve against arrival, not generation', () {
    test('tomorrow + time', () {
      final w = only('Dentist appointment tomorrow at 11:00 AM', at(26, 14));
      expect(w.start, at(27, 11));
      expect(w.end, at(27, 12));
      expect(w.hasTime, isTrue);
    });

    test('today + time range', () {
      final w = only('Team sync Today 5:00 PM - 5:30 PM', at(26, 9));
      expect(w.start, at(26, 17));
      expect(w.end, at(26, 17, 30));
    });

    test('abbreviations and day after tomorrow', () {
      expect(only('see you tmrw', at(26, 20)).start, at(27, 0));
      expect(only('trip is day after tomorrow', at(26, 20)).start, at(28, 0));
    });

    test('in N days', () {
      final w = only('Your data pack expires in 2 days', at(26, 10));
      expect(w.start, at(28, 0));
      expect(w.end, endOfDay(at(28, 0)));
    });

    test('weekdays resolve forward from arrival', () {
      expect(only('call on Monday', at(26, 10)).start, at(28, 0));
      expect(only('party Saturday', at(26, 10)).start, at(26, 0));
      expect(only('party next Saturday', at(26, 10)).start, at(3, 0, 0, 10));
    });
  });

  group('explicit dates', () {
    test('month-day and day-month', () {
      expect(only('Due date Oct 12', at(26, 10)).start, at(12, 0, 0, 10));
      expect(only('Meet on 12th October', at(26, 10)).start, at(12, 0, 0, 10));
      expect(only('Rs 2,450 debited on 26-Sep', at(26, 10)).start, at(26, 0));
      expect(only('Exam 03/10/2026', at(26, 10)).start, at(3, 0, 0, 10));
    });

    test('ranges and multiple mentions', () {
      final windows = relevanceWindows(
        'Goa trip is ON for Dec 12-15, confirm by Friday',
        at(26, 10),
      );
      expect(windows, hasLength(2));
      expect(windows[0].start, at(2, 0, 0, 10)); // Friday
      expect(windows[1].start, at(12, 0, 0, 12));
      expect(windows[1].end, endOfDay(at(15, 0, 0, 12)));
    });

    test('a year-less date near New Year picks the closest year', () {
      final w = only('Flight on Jan 3', DateTime(2026, 12, 30, 10));
      expect(w.start, DateTime(2027, 1, 3));
    });

    test('"1 may" without ordinal or year is not a date', () {
      expect(only('Option 1 may be better', at(26, 10)).explicit, isFalse);
    });
  });

  group('times', () {
    test('a time with no day that is long past at arrival means tomorrow', () {
      expect(only('Meeting at 10 AM', at(26, 23)).start, at(27, 10));
      expect(only('Call at 5 PM', at(26, 14)).start, at(26, 17));
    });

    test('ranges inherit the meridiem of their end', () {
      final w = only('Dinner 9 to 9:30 PM tomorrow', at(26, 12));
      expect(w.start, at(27, 21));
      expect(w.end, at(27, 21, 30));
    });

    test('24-hour clock, and bare single-digit hours read as PM', () {
      expect(only('standup 09:30 tomorrow', at(26, 12)).start, at(27, 9, 30));
      expect(only('tomorrow at 5:30', at(26, 12)).start, at(27, 17, 30));
    });

    test('in N minutes / hours is relative to arrival', () {
      final w = only('Your cab arrives in 20 mins', at(26, 10));
      expect(w.start, at(26, 10, 20));
    });
  });

  group('undated notifications', () {
    test('stay relevant until the end of the day they arrived', () {
      final w = only('Did you eat lunch?', at(26, 9));
      expect(w.explicit, isFalse);
      expect(w.start, at(26, 9));
      expect(w.end, endOfDay(at(26, 9)));
    });

    test('late at night, at least 12 hours so they reach the morning', () {
      expect(only('Call me when free', at(26, 23)).end, at(27, 11));
    });

    test('mentions already over at arrival count as undated', () {
      final w = only('Payment received on 25-Sep', at(26, 10));
      expect(w.explicit, isFalse);
    });
  });

  group('rewriteRelativeDays', () {
    test('rewrites relative days so they are true as of now', () {
      expect(
        rewriteRelativeDays('Client demo is tomorrow at 6:30 PM', at(25, 18), at(26, 13)),
        'Client demo is today at 6:30 PM',
      );
      expect(
        rewriteRelativeDays('Tomorrow 11 AM. Dinner tonight?', at(25, 18), at(26, 13)),
        'Today 11 AM. Dinner last night?',
      );
      expect(
        rewriteRelativeDays('Trip day after tomorrow', at(25, 18), at(26, 13)),
        'Trip tomorrow',
      );
      expect(
        rewriteRelativeDays('see you tomorrow', at(23, 18), at(26, 13)),
        'see you on Thu 24 Sep',
      );
    });

    test('leaves same-day text alone', () {
      const text = 'Dinner tomorrow at 8 PM';
      expect(rewriteRelativeDays(text, at(26, 9), at(26, 13)), text);
    });
  });

  test('a named one-hour range keeps its end time', () {
    final w = only('Online test today between 7:00-8:00 PM', at(25, 12));
    expect(w.hasEndTime, isTrue);
    expect(only('Call at 5 PM', at(26, 14)).hasEndTime, isFalse);
  });

  test('horizon ends at the end of tomorrow', () {
    expect(briefingHorizonEnd(at(26, 21)), endOfDay(at(27, 0)));
  });
}
