import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/core/services/reminders.dart';
import 'package:project_echo/features/todo/data/todo_item.dart';
import 'package:project_echo/features/todo/data/todo_planner.dart';

// Sat 3 Oct 2026, 4:12 PM.
final now = DateTime(2026, 10, 3, 16, 12);

TodoItem item(String? time, {int dayOffset = 0, bool done = false}) => TodoItem(
  id: 1,
  title: 'Tell Rahul about Friday',
  day: DateTime(2026, 10, 3 + dayOffset),
  time: time,
  sort: 0,
  sender: 'Rahul',
  app: 'WhatsApp',
  sourceText: 'Need to know by 8 tonight',
  sourceKey: 'Rahul|1',
  created: now,
  done: done,
);

void main() {
  group('a typed to-do', () {
    test('keeps what to do and reads when', () {
      final plumber = typedItem('call the plumber at 11 tomorrow', 7, now);
      expect(plumber.title, 'Call the plumber');
      expect(plumber.day, DateTime(2026, 10, 4));
      expect(plumber.startsAt, DateTime(2026, 10, 4, 11));
      expect(plumber.sender, 'Added by you');
      expect(plumber.sourceKey, startsWith('you|'));

      final rent = typedItem('pay rent by 5pm', 8, now);
      expect(rent.title, 'Pay rent');
      expect(rent.startsAt, DateTime(2026, 10, 3, 17));

      final gym = typedItem('gym on Monday 7am', 9, now);
      expect(gym.title, 'Gym');
      expect(gym.startsAt, DateTime(2026, 10, 5, 7));
    });

    test('without a time is today, any time', () {
      final laundry = typedItem('Pick up the laundry', 10, now);
      expect(laundry.title, 'Pick up the laundry');
      expect(laundry.day, DateTime(2026, 10, 3));
      expect(laundry.time, isNull);
      expect(laundry.sort, TodoItem.noTimeSort);
    });
  });

  group('Echo’s suggested reminder', () {
    test('20 minutes before the time it names', () {
      expect(
        suggestedReminder(item('8:00 PM'), now),
        DateTime(2026, 10, 3, 19, 40),
      );
      expect(
        suggestedReminder(item('9 AM', dayOffset: 1), now),
        DateTime(2026, 10, 4, 8, 40),
      );
      expect(
        suggestedReminder(item('4 PM to 6 PM', dayOffset: 1), now),
        DateTime(2026, 10, 4, 15, 40),
      );
    });

    test('none without a time, once done, or when it is too close', () {
      expect(suggestedReminder(item(null), now), isNull);
      expect(suggestedReminder(item('8:00 PM', done: true), now), isNull);
      expect(suggestedReminder(item('4:30 PM'), now), isNull);
    });
  });
}
