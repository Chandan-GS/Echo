import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/relevance/briefing_selection.dart';

// Sat 26 Sep 2026.
DateTime at(int day, int hour, [int minute = 0]) =>
    DateTime(2026, 9, day, hour, minute);

RawData note(String sender, String content, DateTime receivedAt,
        {String source = 'Whatsapp'}) =>
    RawData()
      ..source = source
      ..sender = sender
      ..content = content
      ..timestamp = receivedAt;

/// Ten notifications that arrive on Saturday but are about Sunday.
final forTomorrow = [
  note('Dentist', 'Appointment tomorrow at 11:00 AM', at(26, 9)),
  note('Rahul', 'Cricket tmrw 7am, bring the bat', at(26, 10)),
  note('Mom', 'Lunch at our place on Sunday', at(26, 11)),
  note('Ananya', 'Can you review the PR before standup tomorrow?', at(26, 12)),
  note('Priya', 'Movie tickets booked for 27 Sep, 6:30 PM', at(26, 13)),
  note('Landlord', 'Plumber will come tomorrow between 2 to 4 PM', at(26, 14)),
  note('Gym', 'Your trainer session is tomorrow 8:00 AM', at(26, 15)),
  note('Team', 'Release sync tomorrow 17:00 - 17:30', at(26, 16)),
  note('Arjun', 'Pick me up from the airport tomorrow night 10 PM', at(26, 17)),
  note('School', 'PTM is on Sep 27th at 9 AM', at(26, 18)),
];

/// Saturday-only notifications.
final forToday = [
  note('Boss', 'Quick sync today at 5 PM', at(26, 9)),
  note('Friend', 'Did you eat lunch?', at(26, 12)),
  note('Cafe', 'Your table is ready', at(26, 13)),
  note('Late', 'Dinner at 10 PM tonight?', at(26, 18)),
];

void main() {
  test('generated the next morning: all ten for-tomorrow items, no stale ones',
      () {
    final lateNight = note('Sister', 'Call me when you wake up', at(26, 23));
    final items = selectForBriefing(
      [...forTomorrow, ...forToday, lateNight],
      at(27, 7),
    );
    final senders = items.map((i) => i.entry.sender).toSet();

    expect(senders, containsAll(forTomorrow.map((e) => e.sender)));
    expect(senders, isNot(contains('Boss'))); // 5 PM yesterday
    expect(senders, isNot(contains('Friend'))); // undated, yesterday noon
    expect(senders, isNot(contains('Cafe')));
    expect(senders, isNot(contains('Late'))); // 10 PM yesterday
    expect(senders, contains('Sister')); // undated, arrived 11 PM
  });

  test('generated the same evening: tomorrow plus what is still ahead today',
      () {
    final items = selectForBriefing([...forTomorrow, ...forToday], at(26, 21));
    final senders = items.map((i) => i.entry.sender).toSet();

    expect(senders, containsAll(forTomorrow.map((e) => e.sender)));
    expect(senders, contains('Late')); // 10 PM tonight, still ahead
    expect(senders, isNot(contains('Boss'))); // 5 PM, already over
    // Undated items from today are still in their window this evening.
    expect(senders, containsAll(['Friend', 'Cafe']));
  });

  test('things after tomorrow are left out until they are near', () {
    final trip = note('Rahul', 'Goa trip on Oct 3', at(26, 10));
    expect(selectForBriefing([trip], at(26, 12)), isEmpty);
    expect(selectForBriefing([trip], at(30, 7)), isEmpty); // Oct 3 is 3 days out
    // On Fri 2 Oct, Oct 3 is tomorrow.
    expect(
      selectForBriefing([trip], DateTime(2026, 10, 2, 7)).single.entry,
      trip,
    );
  });

  test('dated items come first, in chronological order', () {
    final items = selectForBriefing([...forTomorrow], at(27, 6));
    final starts = items.map((i) => i.window.start).toList();
    expect(starts, orderedEquals([...starts]..sort()));
    // All-day items start at midnight; the first timed one is 7 AM cricket.
    expect(items.firstWhere((i) => i.window.hasTime).entry.sender, 'Rahul');
  });

  test('junk senders/keywords and blocked categories stay out', () {
    final items = selectForBriefing(
      [
        note('Zomato', 'Order arriving tomorrow', at(26, 10)),
        note('Bank', 'Your OTP for tomorrow is 1234', at(26, 10)),
        note('Boss', 'Review tomorrow at 10 AM', at(26, 10), source: 'Slack'),
        note('Mom', 'Temple tomorrow', at(26, 10)),
      ],
      at(26, 20),
      blockedCategories: ['Slack'],
    );
    expect(items.map((i) => i.entry.sender), ['Mom']);
  });

  test('labels are resolved against generation time', () {
    final dentist = forTomorrow.first;
    final item = selectForBriefing([dentist], at(27, 7)).single;
    expect(
      describeWhen(item.window, dentist.timestamp, at(27, 7)),
      'Today (Sun 27 Sep), 11:00 AM',
    );
    expect(
      describeWhen(item.window, dentist.timestamp, at(26, 21)),
      'Tomorrow (Sun 27 Sep), 11:00 AM',
    );

    final undated = note('Sister', 'Call me', at(26, 23, 5));
    final u = selectForBriefing([undated], at(27, 7)).single;
    expect(describeWhen(u.window, undated.timestamp, at(27, 7)),
        'arrived yesterday at 11:05 PM');
  });

  test('the cap drops the least important items, not the latest ones', () {
    final items = selectForBriefing(
      [
        ...forTomorrow,
        note('Newsletter', 'Weekly digest is here', at(26, 20)),
        note('Promo', 'New arrivals in store', at(26, 20, 5)),
      ],
      at(26, 21),
      limit: 10,
    );
    final senders = items.map((i) => i.entry.sender).toSet();
    // All ten dated items survive; the two undated ones are what's cut.
    expect(senders, containsAll(forTomorrow.map((e) => e.sender)));
    expect(senders, isNot(contains('Newsletter')));
    // Still presented chronologically.
    final starts = items.map((i) => i.window.start).toList();
    expect(starts, orderedEquals([...starts]..sort()));
  });

  group('describeEntry', () {
    test('an undated item whose named time was already over says so', () {
      final ishaan = note('Ishaan', 'Quick call at 9 AM today?', at(26, 13, 19));
      final item = selectForBriefing([ishaan], at(26, 14)).single;
      expect(
        describeEntry(ishaan, item.window, at(26, 14)),
        'arrived today at 1:19 PM; mentions Today (Sat 26 Sep), 9:00 AM, already over',
      );
    });

    test('a named range shows both ends; arrival can be appended', () {
      final plumber = note('Landlord', 'Plumber tomorrow 7:00-8:00 PM', at(25, 22, 30));
      final item = selectForBriefing([plumber], at(26, 14)).single;
      expect(describeEntry(plumber, item.window, at(26, 14)),
          'Today (Sat 26 Sep), 7:00 PM to 8:00 PM');
      expect(describeEntry(plumber, item.window, at(26, 14), withArrival: true),
          'Today (Sat 26 Sep), 7:00 PM to 8:00 PM; arrived yesterday at 10:30 PM');
    });
  });

  test('isStillRelevant keeps future-dated notifications past 24 hours', () {
    final trip = note('Rahul', 'Goa trip on Oct 3', at(20, 10));
    expect(isStillRelevant(trip, at(27, 10)), isTrue);
    expect(isStillRelevant(trip, DateTime(2026, 10, 4)), isFalse);
    expect(isStillRelevant(note('X', 'hi', at(20, 10)), at(27, 10)), isFalse);
  });
}
