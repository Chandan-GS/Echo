import 'package:project_echo/core/services/reminders.dart';
import 'package:project_echo/features/todo/data/todo_item.dart';

/// The desktop board's three columns.
enum BoardColumn {
  today('Today'),
  tomorrow('Tomorrow'),
  later('Later');

  final String label;
  const BoardColumn(this.label);

  /// The day a card dropped here goes to. Later means the day after
  /// tomorrow: the owner can move it on from there.
  DateTime dayFrom(DateTime now) =>
      DateTime(now.year, now.month, now.day + index);

  /// The column [item] sits in, or null for a day already gone (those stay
  /// as history and aren't on the board).
  static BoardColumn? of(TodoItem item, DateTime now) {
    final days = daysBetween(now, item.day);
    if (days < 0) return null;
    return days == 0
        ? today
        : days == 1
        ? tomorrow
        : later;
  }
}

/// Whole days from [now]'s date to [day]'s. Counted in UTC so a clock
/// change in between doesn't make a day 23 hours long.
int daysBetween(DateTime now, DateTime day) => DateTime.utc(
  day.year,
  day.month,
  day.day,
).difference(DateTime.utc(now.year, now.month, now.day)).inDays;

/// What goes in [column]: still to do first, by day and time, then what's
/// done, struck through at the bottom.
List<TodoItem> itemsIn(
  BoardColumn column,
  Iterable<TodoItem> items,
  DateTime now,
) {
  int order(TodoItem a, TodoItem b) {
    if (a.done != b.done) return a.done ? 1 : -1;
    final byDay = a.day.compareTo(b.day);
    return byDay != 0 ? byDay : a.sort.compareTo(b.sort);
  }

  return items.where((i) => BoardColumn.of(i, now) == column).toList()
    ..sort(order);
}

/// [items] as cards: one each, except the parts of a message Echo split
/// (source keys "key#1", "key#2"…), which share a card where the first of
/// them would be.
List<List<TodoItem>> cardsOf(List<TodoItem> items) {
  String base(TodoItem i) => i.sourceKey.split('#').first;
  final split = <String, List<TodoItem>>{};
  for (final i in items) {
    if (i.sourceKey.contains('#')) (split[base(i)] ??= []).add(i);
  }
  final cards = <List<TodoItem>>[];
  final placed = <String>{};
  for (final i in items) {
    final parts = split[base(i)];
    if (parts == null || parts.length < 2) {
      cards.add([i]);
    } else if (placed.add(base(i))) {
      cards.add(parts);
    }
  }
  return cards;
}

/// Echo's suggested reminder for each of [items] still to do that has a
/// time and no reminder yet.
List<(TodoItem, DateTime)> offersIn(
  Iterable<TodoItem> items,
  Map<String, DateTime> reminders,
  DateTime now,
) => [
  for (final i in items)
    if (!i.done && !reminders.containsKey(i.sourceKey))
      if (suggestedReminder(i, now) case final at?) (i, at),
];

/// Under a column's name: "Saturday · 4 left".
String columnNote(BoardColumn column, DateTime now, List<TodoItem> items) {
  final day = switch (column) {
    BoardColumn.later => 'This week and after',
    _ => _weekdays[column.dayFrom(now).weekday - 1],
  };
  if (items.isEmpty) return day;
  final left = items.where((i) => !i.done).length;
  return left == 0 ? '$day · all done' : '$day · $left left';
}

/// "Tue" within the coming week, "12 Oct" after it.
String shortDay(DateTime day, DateTime now) => daysBetween(now, day) < 7
    ? _weekdays[day.weekday - 1].substring(0, 3)
    : '${day.day} ${_months[day.month - 1]}';

/// "Tue 6 Oct".
String dayLabel(DateTime d) =>
    '${_weekdays[d.weekday - 1].substring(0, 3)} ${d.day} ${_months[d.month - 1]}';

/// Typed in on the phone or here, rather than made from a message.
bool isTyped(TodoItem item) => item.sourceKey.startsWith('you|');

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
