import 'package:shared_preferences/shared_preferences.dart';

/// Current and best consecutive-day briefing-listening streak.
class StreakInfo {
  final int current;
  final int longest;

  const StreakInfo({required this.current, required this.longest});

  static const zero = StreakInfo(current: 0, longest: 0);
}

/// Tracks how many consecutive days in a row the user has heard their
/// briefing, to reward the daily habit.
///
/// "Heard" is recorded the moment playback *starts* (not on completion) —
/// generous on purpose, so getting interrupted mid-briefing doesn't cost the
/// user their streak.
class StreakService {
  static const _kLastHeardDate = 'streak_last_heard_date';
  static const _kCurrent = 'streak_current';
  static const _kLongest = 'streak_longest';
  static const _kBriefingsHeard = 'briefings_heard_total';

  /// A plain comma-separated list of recent heard date-keys (YYYY-MM-DD), kept
  /// as a single String so the native home-screen widget can read it directly
  /// and compute the day-by-day tracker against the device's current date —
  /// staying accurate even if the app hasn't run in days.
  static const _kHeardCsv = 'streak_heard_csv';

  Future<void> _markHeardToday(SharedPreferences prefs) async {
    final today = _dateKey(DateTime.now());
    final raw = prefs.getString(_kHeardCsv) ?? '';
    final dates = raw.isEmpty ? <String>[] : raw.split(',');
    if (!dates.contains(today)) dates.add(today);
    // Keep only the last ~3 weeks — plenty for any week view.
    dates.sort();
    final trimmed =
        dates.length > 21 ? dates.sublist(dates.length - 21) : dates;
    await prefs.setString(_kHeardCsv, trimmed.join(','));
  }

  /// Records that a briefing was heard today and returns the updated streak.
  /// Calling this more than once on the same day is a no-op beyond the first.
  Future<StreakInfo> recordHeard() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _dateKey(DateTime.now());
    final lastDate = prefs.getString(_kLastHeardDate);
    final current = prefs.getInt(_kCurrent) ?? 0;
    final longest = prefs.getInt(_kLongest) ?? 0;

    if (lastDate == today) {
      // Already recorded today — nothing to do.
      return StreakInfo(current: current, longest: longest);
    }

    final yesterday = _dateKey(DateTime.now().subtract(const Duration(days: 1)));
    final nextCurrent = (lastDate == yesterday) ? current + 1 : 1;
    final nextLongest = nextCurrent > longest ? nextCurrent : longest;

    await prefs.setString(_kLastHeardDate, today);
    await prefs.setInt(_kCurrent, nextCurrent);
    await prefs.setInt(_kLongest, nextLongest);
    // Lifetime count of distinct days a briefing was heard (Profile stat).
    await prefs.setInt(
      _kBriefingsHeard,
      (prefs.getInt(_kBriefingsHeard) ?? 0) + 1,
    );
    await _markHeardToday(prefs);

    return StreakInfo(current: nextCurrent, longest: nextLongest);
  }

  /// Lifetime count of days the user has heard a briefing — a Profile stat.
  Future<int> briefingsHeard() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kBriefingsHeard) ?? 0;
  }

  /// The set of date-keys (YYYY-MM-DD) on which a briefing was heard — powers
  /// the in-app streak calendar.
  Future<Set<String>> heardDates() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kHeardCsv) ?? '';
    if (raw.isEmpty) return <String>{};
    return raw.split(',').where((s) => s.isNotEmpty).toSet();
  }

  /// Builds a date-key the same way the recorder does — so callers can test
  /// membership in [heardDates] for a given day.
  String dateKeyFor(DateTime d) => _dateKey(d);

  /// Reads the streak without recording anything. If the last heard day was
  /// before yesterday, the streak has lapsed — reported as 0 here (but left
  /// on disk untouched; only [recordHeard] mutates persisted state).
  Future<StreakInfo> current() async {
    final prefs = await SharedPreferences.getInstance();
    final lastDate = prefs.getString(_kLastHeardDate);
    final longest = prefs.getInt(_kLongest) ?? 0;
    if (lastDate == null) return StreakInfo(current: 0, longest: longest);

    final today = _dateKey(DateTime.now());
    final yesterday = _dateKey(DateTime.now().subtract(const Duration(days: 1)));
    final stillAlive = lastDate == today || lastDate == yesterday;
    final current = stillAlive ? (prefs.getInt(_kCurrent) ?? 0) : 0;
    return StreakInfo(current: current, longest: longest);
  }

  /// Debug-only: advances the streak by one day and backfills the last
  /// `current` consecutive days as heard, so the calendar reflects a real
  /// multi-day streak without waiting.
  Future<StreakInfo> debugBumpStreak() async {
    final prefs = await SharedPreferences.getInstance();
    final current = (prefs.getInt(_kCurrent) ?? 0) + 1;
    final longest = prefs.getInt(_kLongest) ?? 0;
    final nextLongest = current > longest ? current : longest;

    final now = DateTime.now();
    final dates = List.generate(
      current,
      (i) => _dateKey(now.subtract(Duration(days: i))),
    )..sort();

    await prefs.setString(_kHeardCsv, dates.join(','));
    await prefs.setString(_kLastHeardDate, _dateKey(now));
    await prefs.setInt(_kCurrent, current);
    await prefs.setInt(_kLongest, nextLongest);
    await prefs.setInt(_kBriefingsHeard, current);

    return StreakInfo(current: current, longest: nextLongest);
  }

  /// Debug-only: clears the streak back to zero.
  Future<void> debugResetStreak() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kLastHeardDate);
    await prefs.remove(_kCurrent);
    await prefs.remove(_kLongest);
    await prefs.remove(_kBriefingsHeard);
    await prefs.remove(_kHeardCsv);
  }

  /// Exports the raw streak state for phone→desktop sync.
  Future<Map<String, dynamic>> exportSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'current': prefs.getInt(_kCurrent) ?? 0,
      'longest': prefs.getInt(_kLongest) ?? 0,
      'lastHeardDate': prefs.getString(_kLastHeardDate),
      'heardCsv': prefs.getString(_kHeardCsv) ?? '',
      'total': prefs.getInt(_kBriefingsHeard) ?? 0,
    };
  }

  /// Overwrites the local streak state from a synced snapshot (desktop mirror).
  /// The phone is authoritative, so this replaces rather than merges.
  Future<void> importSnapshot(Map<String, dynamic> snap) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kCurrent, (snap['current'] as num?)?.toInt() ?? 0);
    await prefs.setInt(_kLongest, (snap['longest'] as num?)?.toInt() ?? 0);
    await prefs.setInt(_kBriefingsHeard, (snap['total'] as num?)?.toInt() ?? 0);
    final last = snap['lastHeardDate'] as String?;
    if (last != null) {
      await prefs.setString(_kLastHeardDate, last);
    } else {
      await prefs.remove(_kLastHeardDate);
    }
    await prefs.setString(_kHeardCsv, (snap['heardCsv'] as String?) ?? '');
  }

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
