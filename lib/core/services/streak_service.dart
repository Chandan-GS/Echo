import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Current and best run of days, and the day that can still be mended.
class StreakInfo {
  final int current;
  final int longest;

  /// Yesterday's date-key when it was missed and showing up today keeps the
  /// streak going. Null the rest of the time.
  final String? mendable;

  const StreakInfo({required this.current, required this.longest, this.mendable});

  static const zero = StreakInfo(current: 0, longest: 0);
}

/// What counting today does to a streak.
class StreakStep {
  final int current;
  final int longest;

  /// False when today had already counted.
  final bool advanced;

  /// The missed day this step mended, if it did.
  final String? mended;

  const StreakStep({
    required this.current,
    required this.longest,
    required this.advanced,
    this.mended,
  });
}

/// Days from [from] to [to], both date-keys. Null if either is unreadable.
/// Calendar arithmetic, so daylight saving can't shift it.
int? streakDaysBetween(String from, String to) {
  DateTime? read(String key) {
    final p = key.split('-').map(int.tryParse).toList();
    if (p.length != 3 || p.contains(null)) return null;
    return DateTime.utc(p[0]!, p[1]!, p[2]!);
  }

  final a = read(from);
  final b = read(to);
  return a == null || b == null ? null : b.difference(a).inDays;
}

/// A missed day can be mended the day after, at most once in [mendEveryDays],
/// so skipping every other day doesn't count as a streak.
const mendEveryDays = 7;

bool canMend(String missed, Set<String> mended) => !mended.any((m) {
  final gap = streakDaysBetween(m, missed);
  return gap != null && gap.abs() < mendEveryDays;
});

/// The missed day between [last] and [today] that can still be mended.
String? mendableDay({
  required String? last,
  required int current,
  required String today,
  required String yesterday,
  required Set<String> mended,
}) {
  if (last == null || current <= 0) return null;
  if (streakDaysBetween(last, today) != 2) return null;
  return canMend(yesterday, mended) ? yesterday : null;
}

/// Counts [today]. A mended day holds the chain but adds nothing to it, so the
/// number is always days the owner actually showed up. A clock moved backwards
/// (a timezone change) reads as today already counted, never as a lost streak.
StreakStep stepStreak({
  required String? last,
  required int current,
  required int longest,
  required String today,
  required String yesterday,
  Set<String> mended = const {},
}) {
  final gap = last == null ? null : streakDaysBetween(last, today);
  if (gap != null && gap <= 0) {
    return StreakStep(current: current, longest: longest, advanced: false);
  }
  final mend = mendableDay(
    last: last,
    current: current,
    today: today,
    yesterday: yesterday,
    mended: mended,
  );
  final next = gap == 1 || mend != null ? current + 1 : 1;
  return StreakStep(
    current: next,
    longest: next > longest ? next : longest,
    advanced: true,
    mended: mend,
  );
}

/// Tracks how many days in a row the owner has shown up for the people in
/// their messages. A day counts when the evening wrap is cleared or a briefing
/// is played, whichever comes first.
///
/// Playing is recorded the moment playback *starts* (not on completion) —
/// generous on purpose, so getting interrupted mid-briefing doesn't cost the
/// user their streak.
///
/// Stored under the same keys as before the evening wrap existed, so streaks
/// from older versions carry straight on. Mended days are new and optional.
class StreakService {
  /// Ticks when a day is counted, so the streak card can redraw.
  static final changed = ValueNotifier<int>(0);

  static const _kLastHeardDate = 'streak_last_heard_date';
  static const _kCurrent = 'streak_current';
  static const _kLongest = 'streak_longest';
  static const _kBriefingsHeard = 'briefings_heard_total';
  static const _kLastBriefingDay = 'briefings_heard_last_day';

  /// A plain comma-separated list of recent counted date-keys (YYYY-MM-DD),
  /// kept as a single String so the native home-screen widget can read it
  /// directly and compute the day-by-day tracker against the device's current
  /// date — staying accurate even if the app hasn't run in days.
  static const _kHeardCsv = 'streak_heard_csv';

  /// The counted days that were mended rather than shown up for. Also in
  /// [_kHeardCsv], so the widgets draw them as part of the chain.
  static const _kMendedCsv = 'streak_mended_csv';

  /// Enough for this month's and last month's calendars.
  static const _keepDays = 62;

  static Set<String> _csv(String? raw) => (raw ?? '').isEmpty
      ? <String>{}
      : raw!.split(',').where((s) => s.isNotEmpty).toSet();

  Future<void> _addDay(SharedPreferences prefs, String key, String day) async {
    final dates = {..._csv(prefs.getString(key)), day}.toList()..sort();
    final trimmed = dates.length > _keepDays
        ? dates.sublist(dates.length - _keepDays)
        : dates;
    await prefs.setString(key, trimmed.join(','));
  }

  String _yesterday(DateTime now) =>
      _dateKey(DateTime(now.year, now.month, now.day - 1));

  /// Counts today once, mending yesterday if it can be.
  Future<StreakStep> _countToday(SharedPreferences prefs) async {
    final now = DateTime.now();
    final today = _dateKey(now);
    final step = stepStreak(
      last: prefs.getString(_kLastHeardDate),
      current: prefs.getInt(_kCurrent) ?? 0,
      longest: prefs.getInt(_kLongest) ?? 0,
      today: today,
      yesterday: _yesterday(now),
      mended: _csv(prefs.getString(_kMendedCsv)),
    );
    if (!step.advanced) return step;
    await prefs.setString(_kLastHeardDate, today);
    await prefs.setInt(_kCurrent, step.current);
    await prefs.setInt(_kLongest, step.longest);
    await _addDay(prefs, _kHeardCsv, today);
    final mended = step.mended;
    if (mended != null) {
      await _addDay(prefs, _kHeardCsv, mended);
      await _addDay(prefs, _kMendedCsv, mended);
    }
    changed.value++;
    return step;
  }

  /// A briefing started playing: counts today and returns the updated streak.
  /// Calling this more than once on the same day is a no-op beyond the first.
  Future<StreakInfo> recordHeard() async {
    final prefs = await SharedPreferences.getInstance();
    final step = await _countToday(prefs);
    final today = _dateKey(DateTime.now());
    if (prefs.getString(_kLastBriefingDay) != today) {
      await prefs.setString(_kLastBriefingDay, today);
      // Lifetime count of distinct days a briefing was heard.
      await prefs.setInt(
        _kBriefingsHeard,
        (prefs.getInt(_kBriefingsHeard) ?? 0) + 1,
      );
    }
    return StreakInfo(current: step.current, longest: step.longest);
  }

  /// The evening wrap was cleared: counts today and returns the updated
  /// streak. Safe to call on every clear.
  Future<StreakInfo> recordEveningWrapCleared() async {
    final prefs = await SharedPreferences.getInstance();
    final step = await _countToday(prefs);
    return StreakInfo(current: step.current, longest: step.longest);
  }

  /// Lifetime count of days the user has heard a briefing — a Profile stat.
  Future<int> briefingsHeard() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kBriefingsHeard) ?? 0;
  }

  /// The date-keys (YYYY-MM-DD) that counted — powers the streak calendar.
  Future<Set<String>> heardDates() async {
    final prefs = await SharedPreferences.getInstance();
    return _csv(prefs.getString(_kHeardCsv));
  }

  /// The counted days that were mended, marked differently on the calendar.
  Future<Set<String>> mendedDates() async {
    final prefs = await SharedPreferences.getInstance();
    return _csv(prefs.getString(_kMendedCsv));
  }

  /// Builds a date-key the same way the recorder does — so callers can test
  /// membership in [heardDates] for a given day.
  String dateKeyFor(DateTime d) => _dateKey(d);

  /// Reads the streak without recording anything. Once it can no longer be
  /// mended it has lapsed — reported as 0 here (but left on disk untouched;
  /// only recording mutates persisted state).
  Future<StreakInfo> current() async {
    final prefs = await SharedPreferences.getInstance();
    final lastDate = prefs.getString(_kLastHeardDate);
    final longest = prefs.getInt(_kLongest) ?? 0;
    if (lastDate == null) return StreakInfo(current: 0, longest: longest);

    final now = DateTime.now();
    final today = _dateKey(now);
    final stored = prefs.getInt(_kCurrent) ?? 0;
    final gap = streakDaysBetween(lastDate, today);
    if (gap == null) return StreakInfo(current: 0, longest: longest);
    if (gap <= 1) return StreakInfo(current: stored, longest: longest);
    final mendable = mendableDay(
      last: lastDate,
      current: stored,
      today: today,
      yesterday: _yesterday(now),
      mended: _csv(prefs.getString(_kMendedCsv)),
    );
    return StreakInfo(
      current: mendable == null ? 0 : stored,
      longest: longest,
      mendable: mendable,
    );
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
    await prefs.remove(_kMendedCsv);
    await prefs.remove(_kLastBriefingDay);
  }

  /// Exports the raw streak state for phone→desktop sync.
  Future<Map<String, dynamic>> exportSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'current': prefs.getInt(_kCurrent) ?? 0,
      'longest': prefs.getInt(_kLongest) ?? 0,
      'lastHeardDate': prefs.getString(_kLastHeardDate),
      'heardCsv': prefs.getString(_kHeardCsv) ?? '',
      'mendedCsv': prefs.getString(_kMendedCsv) ?? '',
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
    await prefs.setString(_kMendedCsv, (snap['mendedCsv'] as String?) ?? '');
  }

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
