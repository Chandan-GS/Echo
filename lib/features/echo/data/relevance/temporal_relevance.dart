/// Works out WHEN a notification matters, so a briefing generated at any
/// moment covers exactly what's relevant from then until the end of tomorrow.
///
/// Relative words ("tomorrow", "Friday", "in 2 days") are resolved against the
/// moment the notification ARRIVED, never the moment the briefing runs:
/// "tomorrow" in a message from last night means today. Plain deterministic
/// parsing, no model involved, so the same inputs always give the same answer.
library;

/// A span of time a notification is about.
class RelevanceWindow {
  final DateTime start;
  final DateTime end;

  /// True when the notification's text named this time; false for the
  /// default window given to notifications that mention no date or time.
  final bool explicit;

  /// True when a clock time was named, not just a day.
  final bool hasTime;

  const RelevanceWindow({
    required this.start,
    required this.end,
    required this.explicit,
    required this.hasTime,
  });

  bool overlaps(DateTime from, DateTime to) =>
      !end.isBefore(from) && !start.isAfter(to);

  @override
  String toString() =>
      'RelevanceWindow($start → $end, explicit: $explicit, hasTime: $hasTime)';
}

/// How long a notification that names no date or time stays relevant: until
/// the end of the day it arrived, or [undatedMinimum] after arrival if that's
/// later — so a message from 11 PM still makes the next morning's briefing.
const undatedMinimum = Duration(hours: 12);

/// A time named with no day ("meeting at 10 AM") is taken as the arrival day,
/// unless it's already more than this far in the past at arrival — then it
/// must mean the next day (10 AM said at 11 PM).
const _timeOnlyRollover = Duration(hours: 6);

/// A time mention is attached to a day mention at most this many characters
/// away ("Tomorrow 11:00 AM", "Friday, at 5 PM").
const _attachDistance = 50;

/// End of the briefing's look-ahead: the end of tomorrow, relative to [now].
DateTime briefingHorizonEnd(DateTime now) => endOfDay(_addDays(now, 1));

DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime endOfDay(DateTime d) =>
    DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

DateTime _addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days, d.hour, d.minute);

/// Every window [text] refers to, resolved against [receivedAt]. Mentions of
/// times already over when the notification arrived ("paid on 25 Sep") say
/// nothing about when it matters, so they're ignored; with nothing left, the
/// notification gets a single undated window.
List<RelevanceWindow> relevanceWindows(String text, DateTime receivedAt) {
  final explicit = extractExplicitWindows(text, receivedAt)
      .where((w) => !w.end.isBefore(receivedAt))
      .toList();
  if (explicit.isNotEmpty) return explicit;
  final minimumEnd = receivedAt.add(undatedMinimum);
  final dayEnd = endOfDay(receivedAt);
  return [
    RelevanceWindow(
      start: receivedAt,
      end: minimumEnd.isAfter(dayEnd) ? minimumEnd : dayEnd,
      explicit: false,
      hasTime: false,
    ),
  ];
}

/// Windows for the dates and times [text] names explicitly (empty if none).
List<RelevanceWindow> extractExplicitWindows(String text, DateTime receivedAt) {
  final taken = <_Span>[];
  final days = _findDays(text, receivedAt, taken);
  final times = _findTimes(text, taken);
  final instants = _findRelativeInstants(text, receivedAt, taken);

  final windows = <RelevanceWindow>[...instants];
  final timesByDay = <_DayMention, List<_TimeMention>>{};
  final unattached = <_TimeMention>[];

  for (final t in times) {
    _DayMention? nearest;
    var best = _attachDistance + 1;
    for (final d in days) {
      final distance = t.span.distanceTo(d.span);
      if (distance < best) {
        best = distance;
        nearest = d;
      }
    }
    if (nearest == null) {
      unattached.add(t);
    } else {
      timesByDay.putIfAbsent(nearest, () => []).add(t);
    }
  }

  for (final d in days) {
    final attached = timesByDay[d];
    if (attached == null) {
      windows.add(
        RelevanceWindow(
          start: startOfDay(d.first),
          end: endOfDay(d.last),
          explicit: true,
          hasTime: false,
        ),
      );
    } else {
      for (final t in attached) {
        windows.add(t.on(d.first));
      }
    }
  }

  for (final t in unattached) {
    var window = t.on(receivedAt);
    if (window.start.isBefore(receivedAt.subtract(_timeOnlyRollover))) {
      window = t.on(_addDays(receivedAt, 1));
    }
    windows.add(window);
  }

  windows.sort((a, b) => a.start.compareTo(b.start));
  return windows;
}

// ── Internals ───────────────────────────────────────────────────────────────

class _Span {
  final int start;
  final int end;
  const _Span(this.start, this.end);

  bool overlaps(_Span o) => start < o.end && o.start < end;

  int distanceTo(_Span o) {
    if (overlaps(o)) return 0;
    return end <= o.start ? o.start - end : start - o.end;
  }
}

class _DayMention {
  final _Span span;
  final DateTime first;
  final DateTime last;
  _DayMention(this.span, this.first, [DateTime? last]) : last = last ?? first;
}

class _TimeMention {
  final _Span span;
  final int startMinutes;
  final int? endMinutes;
  const _TimeMention(this.span, this.startMinutes, this.endMinutes);

  RelevanceWindow on(DateTime day) {
    final start = DateTime(day.year, day.month, day.day, 0, startMinutes);
    DateTime end;
    if (endMinutes == null) {
      end = start.add(const Duration(hours: 1));
    } else {
      end = DateTime(day.year, day.month, day.day, 0, endMinutes!);
      if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
    }
    return RelevanceWindow(
      start: start,
      end: end,
      explicit: true,
      hasTime: true,
    );
  }
}

const _monthPattern =
    r'(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|'
    r'aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\.?';

const _ordinal = r'(?:st|nd|rd|th)?';

const _rangeSep = r'\s*(?:-|–|—|to)\s*';

int _monthNumber(String m) => const [
      'jan', 'feb', 'mar', 'apr', 'may', 'jun',
      'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
    ].indexOf(m.substring(0, 3).toLowerCase()) +
    1;

const _weekdays = {
  'monday': DateTime.monday,
  'tuesday': DateTime.tuesday,
  'tues': DateTime.tuesday,
  'wednesday': DateTime.wednesday,
  'thursday': DateTime.thursday,
  'thurs': DateTime.thursday,
  'friday': DateTime.friday,
  'saturday': DateTime.saturday,
  'sunday': DateTime.sunday,
};

const _smallNumbers = {
  'a': 1, 'an': 1, 'one': 1, 'two': 2, 'three': 3, 'four': 4,
  'five': 5, 'six': 6, 'seven': 7, 'ten': 10, 'fifteen': 15,
  'twenty': 20, 'thirty': 30,
};

int? _count(String s) => int.tryParse(s) ?? _smallNumbers[s.toLowerCase()];

/// Runs [pattern] over [text], skipping matches that overlap an earlier,
/// higher-priority match, and records the accepted spans in [taken].
void _scan(
  String text,
  String pattern,
  List<_Span> taken,
  bool Function(RegExpMatch m, _Span span) accept,
) {
  for (final m in RegExp(pattern, caseSensitive: false).allMatches(text)) {
    final span = _Span(m.start, m.end);
    if (taken.any(span.overlaps)) continue;
    if (accept(m, span)) taken.add(span);
  }
}

/// A calendar date from day/month (and optional year). Without a year, picks
/// the year that puts the date closest to [anchor].
DateTime? _date(int day, int month, int? year, DateTime anchor) {
  DateTime? build(int y) {
    final d = DateTime(y, month, day);
    return (d.month == month && d.day == day) ? d : null;
  }

  if (year != null) {
    return build(year < 100 ? 2000 + year : year);
  }
  final base = startOfDay(anchor);
  DateTime? best;
  for (final y in [anchor.year - 1, anchor.year, anchor.year + 1]) {
    final d = build(y);
    if (d == null) continue;
    if (best == null ||
        d.difference(base).abs() < best.difference(base).abs()) {
      best = d;
    }
  }
  return best;
}

List<_DayMention> _findDays(String text, DateTime anchor, List<_Span> taken) {
  final days = <_DayMention>[];
  final today = startOfDay(anchor);

  // ISO: 2026-09-27
  _scan(text, r'\b(\d{4})-(\d{2})-(\d{2})\b', taken, (m, span) {
    final d = _date(
      int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!), anchor);
    if (d != null) days.add(_DayMention(span, d));
    return d != null;
  });

  // Numeric, day first (Indian convention), year required so fractions and
  // ratios don't match: 27/09/2026, 27-9-26, 27.09.2026
  _scan(text, r'\b(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4}|\d{2})\b', taken,
      (m, span) {
    final d = _date(
      int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!), anchor);
    if (d != null) days.add(_DayMention(span, d));
    return d != null;
  });

  // Month first, optional day range and year: Oct 12, December 12-15, Sep 27th, 2026
  _scan(
      text,
      '\\b$_monthPattern\\s+(\\d{1,2})$_ordinal'
      '(?:$_rangeSep(\\d{1,2})$_ordinal)?(?:,?\\s+(\\d{4}))?\\b',
      taken, (m, span) {
    final month = _monthNumber(m[1]!);
    final year = m[4] == null ? null : int.parse(m[4]!);
    final first = _date(int.parse(m[2]!), month, year, anchor);
    if (first == null) return false;
    final last =
        m[3] == null ? first : _date(int.parse(m[3]!), month, first.year, anchor);
    days.add(_DayMention(span, first, last ?? first));
    return true;
  });

  // Day first, optional day range and year: 12 Oct, 12th of October, 26-Sep, 12-15 Dec 2026
  _scan(
      text,
      '\\b(\\d{1,2})$_ordinal(?:$_rangeSep(\\d{1,2})$_ordinal)?'
      '(?:\\s+of)?[\\s\\-]*$_monthPattern(?:[\\s,\\-]+(\\d{4}))?\\b',
      taken, (m, span) {
    // "Option 1 may be better" isn't May 1st: a bare "<n> may" needs an
    // ordinal or a year to count as a date.
    if (m[3]!.toLowerCase() == 'may' &&
        m[4] == null &&
        !RegExp(r'\d(?:st|nd|rd|th)', caseSensitive: false).hasMatch(m[0]!)) {
      return false;
    }
    final month = _monthNumber(m[3]!);
    final year = m[4] == null ? null : int.parse(m[4]!);
    final first = _date(int.parse(m[1]!), month, year, anchor);
    if (first == null) return false;
    final last =
        m[2] == null ? first : _date(int.parse(m[2]!), month, first.year, anchor);
    days.add(_DayMention(span, first, last ?? first));
    return true;
  });

  _scan(text, r'\bday after (?:tomorrow|tmrw|tmr)\b', taken, (m, span) {
    days.add(_DayMention(span, _addDays(today, 2)));
    return true;
  });

  _scan(
      text,
      r'\b(?:tomorrow|tomorrows|tmrw|tmr|tmrrw|tomorow|tommorow|tommorrow|2morrow|2moro)\b',
      taken, (m, span) {
    days.add(_DayMention(span, _addDays(today, 1)));
    return true;
  });

  _scan(
      text,
      r'\b(?:today|todays|tonight|tonite|this (?:morning|afternoon|evening))\b',
      taken, (m, span) {
    days.add(_DayMention(span, today));
    return true;
  });

  _scan(text, r'\byesterday\b', taken, (m, span) {
    days.add(_DayMention(span, _addDays(today, -1)));
    return true;
  });

  _scan(
      text,
      r'\bin (\d+|a|an|one|two|three|four|five|six|seven|ten|fifteen|twenty|thirty) (days?|weeks?)\b',
      taken, (m, span) {
    final n = _count(m[1]!);
    if (n == null) return false;
    final perUnit = m[2]!.toLowerCase().startsWith('week') ? 7 : 1;
    days.add(_DayMention(span, _addDays(today, n * perUnit)));
    return true;
  });

  _scan(text, r'\bthis weekend\b', taken, (m, span) {
    // Sat/Sun of the current week; on Sunday that's today alone.
    final toSaturday = (DateTime.saturday - today.weekday) % 7;
    final saturday = today.weekday == DateTime.sunday
        ? today
        : _addDays(today, toSaturday);
    final sunday = today.weekday == DateTime.sunday
        ? today
        : _addDays(saturday, 1);
    days.add(_DayMention(span, saturday, sunday));
    return true;
  });

  _scan(text, r'\bnext week\b', taken, (m, span) {
    final toMonday = 8 - today.weekday; // 1..7 days ahead
    final monday = _addDays(today, toMonday);
    days.add(_DayMention(span, monday, _addDays(monday, 6)));
    return true;
  });

  // Weekday names resolve forward from arrival: "Friday" said on a Friday is
  // that same day; "next Friday" always means a later one.
  _scan(
      text,
      r'\b(next\s+|this\s+|coming\s+)?(monday|tuesday|tues|wednesday|thursday|thurs|friday|saturday|sunday)\b',
      taken, (m, span) {
    final target = _weekdays[m[2]!.toLowerCase()]!;
    var delta = (target - today.weekday) % 7;
    if (delta == 0 && (m[1] ?? '').trim().toLowerCase() == 'next') delta = 7;
    days.add(_DayMention(span, _addDays(today, delta)));
    return true;
  });

  return days;
}

const _meridiem = r'(a\.?m\.?|p\.?m\.?)(?![a-z])';

int _toMinutes(int hour, int minute, String? meridiem) {
  var h = hour % 12;
  final m = meridiem?.toLowerCase().replaceAll('.', '');
  if (m == 'pm') h += 12;
  if (m == null) h = hour;
  return h * 60 + minute;
}

bool _validClock(int hour, int minute, {required bool twelveHour}) =>
    minute >= 0 &&
    minute < 60 &&
    (twelveHour ? hour >= 1 && hour <= 12 : hour >= 0 && hour <= 23);

List<_TimeMention> _findTimes(String text, List<_Span> taken) {
  final times = <_TimeMention>[];

  // Ranges ending in AM/PM; the start inherits the end's meridiem when it has
  // none ("9 to 9:30 PM"), unless that would put it after the end ("11 to 1 PM").
  _scan(
      text,
      '\\b(\\d{1,2})(?:[:.](\\d{2}))?\\s*(?:$_meridiem)?$_rangeSep'
      '(\\d{1,2})(?:[:.](\\d{2}))?\\s*$_meridiem',
      taken, (m, span) {
    final h1 = int.parse(m[1]!), m1 = int.parse(m[2] ?? '0');
    final h2 = int.parse(m[4]!), m2 = int.parse(m[5] ?? '0');
    if (!_validClock(h1, m1, twelveHour: true) ||
        !_validClock(h2, m2, twelveHour: true)) {
      return false;
    }
    final end = _toMinutes(h2, m2, m[6]);
    var start = _toMinutes(h1, m1, m[3] ?? m[6]);
    if (m[3] == null && start > end) start = _toMinutes(h1, m1, 'am');
    times.add(_TimeMention(span, start, end));
    return true;
  });

  _scan(text, '\\b(\\d{1,2})(?:[:.](\\d{2}))?\\s*$_meridiem', taken,
      (m, span) {
    final h = int.parse(m[1]!), min = int.parse(m[2] ?? '0');
    if (!_validClock(h, min, twelveHour: true)) return false;
    times.add(_TimeMention(span, _toMinutes(h, min, m[3]), null));
    return true;
  });

  // 24-hour clock ranges and single times: 17:00 - 18:30, 09:15. A bare
  // single-digit hour from 1 to 7 ("at 5:30") is read as PM — nobody books a
  // 5:30 AM meeting without saying so.
  int clock(String h, String min) {
    var hour = int.parse(h);
    if (h.length == 1 && hour >= 1 && hour <= 7) hour += 12;
    return hour * 60 + int.parse(min);
  }

  _scan(
      text,
      '\\b([01]?\\d|2[0-3]):([0-5]\\d)$_rangeSep([01]?\\d|2[0-3]):([0-5]\\d)\\b',
      taken, (m, span) {
    times.add(_TimeMention(span, clock(m[1]!, m[2]!), clock(m[3]!, m[4]!)));
    return true;
  });

  _scan(text, r'\b([01]?\d|2[0-3]):([0-5]\d)\b', taken, (m, span) {
    times.add(_TimeMention(span, clock(m[1]!, m[2]!), null));
    return true;
  });

  _scan(text, r'\bnoon\b', taken, (m, span) {
    times.add(_TimeMention(span, 12 * 60, null));
    return true;
  });

  times.sort((a, b) => a.span.start.compareTo(b.span.start));
  return times;
}

/// "in 2 hours", "in 30 mins": a one-hour window starting that long after
/// arrival.
List<RelevanceWindow> _findRelativeInstants(
  String text,
  DateTime anchor,
  List<_Span> taken,
) {
  final windows = <RelevanceWindow>[];
  _scan(
      text,
      r'\bin (\d+|a|an|one|two|three|four|five|six|seven|ten|fifteen|twenty|thirty) (hours?|hrs?|minutes?|mins?)\b',
      taken, (m, span) {
    final n = _count(m[1]!);
    if (n == null) return false;
    final unit = m[2]!.toLowerCase();
    final offset = unit.startsWith('h')
        ? Duration(hours: n)
        : Duration(minutes: n);
    final start = anchor.add(offset);
    windows.add(
      RelevanceWindow(
        start: start,
        end: start.add(const Duration(hours: 1)),
        explicit: true,
        hasTime: true,
      ),
    );
    return true;
  });
  return windows;
}
