import 'package:project_echo/core/utils/time_utils.dart';

/// Preference keys the schedule reads: it runs in a background isolate, so
/// it reads them directly rather than through [SettingsCubit].
const briefingEnabledKey = 'briefing_enabled';
const eveningWrapEnabledKey = 'evening_wrap_enabled';
const eveningWrapTimeKey = 'evening_wrap_time';

const defaultEveningWrapTime = '21:30';

/// The evening wrap's choices, "HH:mm".
const eveningWrapTimes = ['20:30', '21:00', '21:30', '22:00', '22:30'];

/// A stored wrap time, or the default when it's missing or malformed.
String eveningWrapTimeOrDefault(String? stored) =>
    stored != null && parseBriefingTime(stored) != null
    ? stored
    : defaultEveningWrapTime;

/// "21:30" → "9:30 PM". Anything malformed comes back as it is.
String clockLabel(String time) {
  final t = parseBriefingTime(time);
  if (t == null) return time;
  final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final minute = t.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// ["07:00", "19:00"] → "7:00 AM and 7:00 PM".
String joinClockLabels(List<String> times) {
  final labels = times.map(clockLabel).toList();
  if (labels.isEmpty) return '';
  if (labels.length == 1) return labels.single;
  return '${labels.sublist(0, labels.length - 1).join(', ')} '
      'and ${labels.last}';
}

/// 540 → "9 AM", 570 → "9:30 AM".
String _minutesLabel(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  final hour = h % 12 == 0 ? 12 : h % 12;
  final suffix = h < 12 ? 'AM' : 'PM';
  return m == 0
      ? '$hour $suffix'
      : '$hour:${m.toString().padLeft(2, '0')} $suffix';
}

/// "Weekdays, 9 AM to 1 PM". [days] are 1 = Monday … 7 = Sunday.
String quietWhenLabel(Set<int> days, int startMin, int endMin) {
  final when = days.length == 7
      ? 'Every day'
      : days.length == 5 && days.containsAll(const {1, 2, 3, 4, 5})
      ? 'Weekdays'
      : days.length == 2 && days.containsAll(const {6, 7})
      ? 'Weekends'
      : days.length == 1
      ? '1 day a week'
      : '${days.length} days a week';
  return '$when, ${_minutesLabel(startMin)} to ${_minutesLabel(endMin)}';
}
