/// A parsed hour/minute pair from a stored "HH:mm" briefing time string.
class BriefingTime {
  final int hour;
  final int minute;

  const BriefingTime(this.hour, this.minute);

  /// Minutes since midnight — convenient for ordering/comparisons.
  int get minutesOfDay => hour * 60 + minute;

  @override
  bool operator ==(Object other) =>
      other is BriefingTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

/// Safely parses a 24-hour "HH:mm" time string.
///
/// Returns `null` for anything malformed — missing colon, empty parts,
/// non-numeric values, or hours/minutes out of range. This guards every
/// scheduling/countdown call site that previously used `int.parse` (or an
/// unchecked `parts[1]`) directly and would throw a [FormatException] or
/// [RangeError] on corrupted persisted preferences.
BriefingTime? parseBriefingTime(String raw) {
  final parts = raw.trim().split(':');
  if (parts.length != 2) return null;

  final hour = int.tryParse(parts[0].trim());
  final minute = int.tryParse(parts[1].trim());
  if (hour == null || minute == null) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;

  return BriefingTime(hour, minute);
}

/// A briefing slot that has come due: the slot's time, and the key it's
/// recorded under once it has run (`yyyy-MM-dd_<stored time>`, dated the day
/// the slot fell on, so a 23:59 slot caught at 00:01 still belongs to the
/// day before).
typedef DueBriefingSlot = ({String key, BriefingTime time});

/// The briefing slot an alarm firing at [now] should run, or null when
/// there's nothing to do.
///
/// Briefing alarms are inexact, so Android may deliver one minutes or hours
/// after its time. Rather than matching the firing time to a slot, this takes
/// the most recent slot in [times] that has already started (looking back
/// across midnight), and runs it unless [lastRunKey] says it already ran. A
/// slot older than [maxLateness] is left for its next turn, so a phone
/// switched on in the small hours doesn't deliver yesterday's morning
/// briefing. Malformed entries are skipped.
DueBriefingSlot? dueBriefingSlot({
  required DateTime now,
  required List<String> times,
  String? lastRunKey,
  Duration maxLateness = const Duration(hours: 12),
}) {
  DueBriefingSlot? latest;
  DateTime? latestAt;
  for (final raw in times) {
    final time = parseBriefingTime(raw);
    if (time == null) continue;
    var at = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    if (at.isAfter(now)) {
      at = DateTime(now.year, now.month, now.day - 1, time.hour, time.minute);
    }
    if (latestAt == null || at.isAfter(latestAt)) {
      latestAt = at;
      latest = (key: '${_isoDate(at)}_$raw', time: time);
    }
  }
  if (latest == null || latestAt == null) return null;
  if (now.difference(latestAt) > maxLateness) return null;
  if (latest.key == lastRunKey) return null;
  return latest;
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
