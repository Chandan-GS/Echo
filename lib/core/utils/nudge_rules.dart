import 'dart:math' as math;

import 'package:project_echo/core/utils/time_utils.dart';

// The rules behind Echo's two gentle reminders (the day-one evening note and
// the one nudge after missed mornings), and the "tomorrow at 7:00 AM" wording
// Home shows before the first briefing. Pure, with the clock passed in, so
// they can be tested without a device; GentleNudges does the scheduling.

/// The calendar day of [d], as a UTC midnight. Days are compared and stepped
/// in UTC so a daylight-saving change (a 23- or 25-hour local day) can't make
/// one day look like none, or two.
DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// Parses a `YYYY-MM-DD` key (as StreakService writes them) into its day.
DateTime? _dayFromKey(String key) {
  final parts = key.trim().split('-');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  return DateTime.utc(y, m, d);
}

/// How many calendar days [to] is after [from] (0 for the same day).
int calendarDaysBetween(DateTime from, DateTime to) =>
    _day(to).difference(_day(from)).inDays;

/// The `YYYY-MM-DD` key for [d]'s calendar day.
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// The next time at or after [now] that one of [times] falls, or null when
/// none parse. Tomorrow's slot is built from the date, not by adding 24
/// hours, so it stays on its clock time across a daylight-saving change.
DateTime? nextBriefingAt(DateTime now, List<String> times) {
  DateTime? next;
  for (final raw in times) {
    final t = parseBriefingTime(raw);
    if (t == null) continue;
    var at = DateTime(now.year, now.month, now.day, t.hour, t.minute);
    if (at.isBefore(now)) {
      at = DateTime(now.year, now.month, now.day + 1, t.hour, t.minute);
    }
    if (next == null || at.isBefore(next)) next = at;
  }
  return next;
}

/// "7:00 AM", the way Home writes times.
String briefingClock(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// When [next] is, said from [now]: "today at 7:00 AM", "tomorrow at
/// 7:00 AM", or, further out, "on Friday at 7:00 AM". Decided by calendar
/// day, so 11 PM's "tomorrow at 7:00 AM" is right and 1 AM's is "today".
String briefingWhenLabel(DateTime next, DateTime now) {
  final clock = briefingClock(next);
  return switch (calendarDaysBetween(now, next)) {
    <= 0 => 'today at $clock',
    1 => 'tomorrow at $clock',
    _ => 'on ${_weekdays[next.weekday - 1]} at $clock',
  };
}

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// The hour of the day-one evening note.
const dayOneNudgeHour = 20;

/// When the day-one evening note should fire: [dayOneNudgeHour] today, as
/// long as that's still ahead of [now] and comes before the first briefing
/// ([firstBriefing]). Null when it's too late today, or the briefing comes
/// first (a briefing set for 6 PM is its own reminder).
DateTime? dayOneNudgeAt({
  required DateTime now,
  required DateTime? firstBriefing,
}) {
  if (firstBriefing == null) return null;
  final at = DateTime(now.year, now.month, now.day, dayOneNudgeHour);
  if (!at.isAfter(now) || !at.isBefore(firstBriefing)) return null;
  return at;
}

/// The day-one note's text, from what Echo has heard so far today
/// ([heardToday]). Null when it has heard nothing: "Echo has heard 0
/// messages" helps no one, and more likely means it can't read them yet.
String? dayOneNudgeBody(int heardToday, DateTime firstBriefing) {
  if (heardToday <= 0) return null;
  final messages = heardToday == 1 ? '1 message' : '$heardToday messages';
  return 'Echo has heard $messages today. Your first briefing is ready at '
      '${briefingClock(firstBriefing)}.';
}

/// Whether this morning's briefing notification should carry the one gentle
/// nudge for missed mornings.
///
/// It's due when the owner heard no briefing on either of the two days
/// before [now] (nor yet today), both of which were scheduled mornings: Echo
/// had been installed ([firstLaunch]) by the first briefing time of the
/// earlier one, so it's never sent in the first days. One per lapse: once
/// sent ([lastNudgeDate]), nothing more until a briefing is heard again on
/// or after that day. [heardDates] are StreakService's `YYYY-MM-DD` keys.
bool missedMorningsNudgeDue({
  required DateTime now,
  required Iterable<String> heardDates,
  required List<String> briefingTimes,
  required DateTime? firstLaunch,
  String? lastNudgeDate,
}) {
  final slots = briefingTimes.map(parseBriefingTime).nonNulls.toList();
  if (slots.isEmpty || firstLaunch == null) return false;

  final heard = heardDates.map(_dayFromKey).nonNulls.toSet();
  final today = _day(now);
  final yesterday = today.subtract(const Duration(days: 1));
  final dayBefore = today.subtract(const Duration(days: 2));
  if (heard.contains(today) ||
      heard.contains(yesterday) ||
      heard.contains(dayBefore)) {
    return false;
  }

  // Both missed mornings must have been scheduled ones.
  final installed = _day(firstLaunch);
  final earliestSlot = slots.map((s) => s.minutesOfDay).reduce(math.min);
  final hadBoth =
      installed.isBefore(dayBefore) ||
      (installed == dayBefore &&
          firstLaunch.hour * 60 + firstLaunch.minute <= earliestSlot);
  if (!hadBoth) return false;

  final nudged = lastNudgeDate == null ? null : _dayFromKey(lastNudgeDate);
  if (nudged != null) {
    final lastHeard = heard.isEmpty
        ? null
        : heard.reduce((a, b) => a.isAfter(b) ? a : b);
    // Still the same lapse: nothing heard since the nudge.
    if (lastHeard == null || lastHeard.isBefore(nudged)) return false;
  }
  return true;
}
