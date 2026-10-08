import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/features/echo/presentation/widgets/home_glance.dart';
import 'package:project_echo/features/todo/data/todo_item.dart';

TodoItem _item(int id, String? time, DateTime day, {bool done = false}) =>
    TodoItem(
      id: id,
      title: 'Item $id',
      day: day,
      time: time,
      sort: 0,
      sender: 'Didi',
      app: 'WhatsApp',
      sourceText: 'x',
      sourceKey: 'k$id',
      done: done,
      created: day,
    );

void main() {
  final now = DateTime(2026, 9, 26, 18, 48);
  final today = DateTime(2026, 9, 26);
  final tomorrow = DateTime(2026, 9, 27);

  test(
    'timed, not done, from now until the end of tomorrow, soonest first',
    () {
      final stops = dayStops([
        _item(1, '10 PM', tomorrow),
        _item(2, '8:00 PM', today),
        _item(3, null, today), // no time
        _item(4, '9 AM', today), // already passed
        _item(5, '9 PM', today, done: true),
        _item(6, '4 PM to 6 PM', tomorrow),
        _item(7, '9 AM', DateTime(2026, 9, 28)), // after tomorrow
      ], now);
      expect(stops.map((s) => s.item.id), [2, 6, 1]);
      expect(stops.first.at, DateTime(2026, 9, 26, 20));
      expect(stops[1].at, DateTime(2026, 9, 27, 16));
    },
  );

  test('something that started a few minutes ago still counts', () {
    final stops = dayStops([_item(1, '6:40 PM', today)], now);
    expect(stops, hasLength(1));
  });
}
