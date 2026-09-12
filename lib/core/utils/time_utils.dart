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
