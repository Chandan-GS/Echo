import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/core/services/reminder_settings.dart';
import 'package:project_echo/core/services/reminders.dart';
import 'package:project_echo/features/profile/data/week_stats.dart';
import 'package:project_echo/features/todo/data/todo_item.dart';

// Sat 3 Oct 2026, 4:12 PM.
final now = DateTime(2026, 10, 3, 16, 12);

TodoItem todo(int id, {DateTime? doneAt, String? time}) => TodoItem(
  id: id,
  title: 'Item $id',
  day: DateTime(2026, 10, 3),
  time: time,
  sort: 0,
  sender: '',
  app: '',
  sourceText: '',
  sourceKey: 'k$id',
  created: now,
  done: doneAt != null,
  doneAt: doneAt,
);

void main() {
  test('the week counts what happened in the last seven days', () {
    final week = WeekStats.summarise(
      items: [
        todo(1, doneAt: DateTime(2026, 10, 3, 9)),
        todo(2, doneAt: DateTime(2026, 9, 27, 8)), // first day of the week
        todo(3, doneAt: DateTime(2026, 9, 26, 22)), // before it
        todo(4),
      ],
      replies: [DateTime(2026, 10, 2), DateTime(2026, 9, 20)],
      readByDay: [10, 20, 30, 40, 50, 60, 70],
      now: now,
    );
    expect(week.todosDone, 2);
    expect(week.replies, 1);
    expect(week.read, 280);
    expect(week.from, DateTime(2026, 9, 27));
  });

  group('reminder settings', () {
    tearDown(() {
      ReminderSettings.lead.value = const Duration(minutes: 20);
      ReminderSettings.suggest.value = true;
    });

    test('the lead time moves Echo’s suggestion', () {
      ReminderSettings.lead.value = const Duration(hours: 1);
      expect(
        suggestedReminder(todo(1, time: '8:00 PM'), now),
        DateTime(2026, 10, 3, 19),
      );
    });

    test('suggestions can be turned off', () {
      ReminderSettings.suggest.value = false;
      expect(suggestedReminder(todo(1, time: '8:00 PM'), now), isNull);
    });

    test('labels read naturally', () {
      expect(ReminderSettings.label(const Duration(minutes: 20)), '20 minutes');
      expect(ReminderSettings.label(const Duration(hours: 1)), '1 hour');
    });
  });
}
