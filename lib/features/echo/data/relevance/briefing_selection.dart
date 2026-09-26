import 'dart:math' as math;

import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/relevance/temporal_relevance.dart';

/// A notification chosen for the briefing, with the window that got it in.
class BriefingItem {
  final RawData entry;
  final RelevanceWindow window;
  const BriefingItem(this.entry, this.window);
}

/// Senders and phrases that are never briefing material (promos, OTPs,
/// transactional noise).
const _junkSenders = [
  'zomato', 'swiggy', 'myntra', 'lenskart', 'amazon', 'uber', 'hdfc',
  'credit card', 'makemytrip', 'apollo', 'dominos', 'jio', 'urban company',
  'blinkit', 'flipkart', 'quora', 'linkedin', 'medium',
];
const _junkKeywords = ['% off', 'otp', 'flash sale', 'discount', 'free'];

/// The display name a source is grouped under in the Vault, after the user's
/// renames.
String displaySource(String source, Map<String, String> aliases) {
  final key = source.trim();
  final normalized = key.isEmpty
      ? 'Unknown'
      : '${key[0].toUpperCase()}${key.substring(1).toLowerCase()}';
  return aliases[normalized] ?? normalized;
}

/// Picks what a briefing generated at [now] should cover: notifications whose
/// relevance window overlaps now → end of tomorrow. Anything whose time has
/// passed, or that's about later than tomorrow, is left out.
///
/// When more than [limit] qualify (the on-device model's context is small),
/// the least important are dropped — dated items outrank undated ones, then
/// similarity to [priorityVector] (phone) or recency (desktop, where synced
/// notifications carry no embeddings) decides. What's kept is returned dated
/// first, chronologically, then undated by importance.
List<BriefingItem> selectForBriefing(
  Iterable<RawData> entries,
  DateTime now, {
  Map<String, String> aliases = const {},
  List<String> blockedCategories = const [],
  List<double>? priorityVector,
  int limit = 15,
}) {
  final horizonEnd = briefingHorizonEnd(now);

  // Latest copy of each distinct content wins.
  final unique = <String, RawData>{};
  final sorted = entries.toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  for (final e in sorted) {
    if (blockedCategories.contains(displaySource(e.source, aliases))) continue;
    final sender = e.sender.toLowerCase();
    final content = e.content.toLowerCase();
    if (_junkSenders.any(sender.contains)) continue;
    if (_junkKeywords.any(content.contains)) continue;
    unique[e.content] = e;
  }

  final dated = <BriefingItem>[];
  final undated = <BriefingItem>[];
  for (final e in unique.values) {
    final windows = relevanceWindows('${e.sender} ${e.content}', e.timestamp);
    final inHorizon = windows.where((w) => w.overlaps(now, horizonEnd));
    if (inHorizon.isEmpty) continue;
    final window = inHorizon.first; // windows are sorted by start
    (window.explicit ? dated : undated).add(BriefingItem(e, window));
  }

  // Importance for the cap: a named date/time is a strong signal on its own.
  final importance = <BriefingItem, double>{
    for (final i in [...dated, ...undated])
      i: (i.window.explicit ? 1.0 : 0.0) +
          (priorityVector != null
              ? cosineSimilarity(priorityVector, i.entry.embedding)
              : i.entry.timestamp.millisecondsSinceEpoch / 1e15),
  };
  final kept = ([...dated, ...undated]
        ..sort((a, b) => importance[b]!.compareTo(importance[a]!)))
      .take(limit)
      .toSet();

  dated
    ..retainWhere(kept.contains)
    ..sort((a, b) => a.window.start.compareTo(b.window.start));
  undated
    ..retainWhere(kept.contains)
    ..sort((a, b) => importance[b]!.compareTo(importance[a]!));
  return [...dated, ...undated];
}

double cosineSimilarity(List<double>? a, List<double>? b) {
  if (a == null || b == null || a.length != b.length) return 0.0;
  var dot = 0.0, normA = 0.0, normB = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  if (normA == 0 || normB == 0) return 0.0;
  return dot / (math.sqrt(normA) * math.sqrt(normB));
}

/// Whether [entry] still refers to anything at or after [now] — used to keep
/// a notification past the usual 24h retention while its time is still ahead.
bool isStillRelevant(RawData entry, DateTime now) =>
    relevanceWindows('${entry.sender} ${entry.content}', entry.timestamp)
        .any((w) => !w.end.isBefore(now));

/// The full label for [e] shown to a model: when it applies ([window]), plus
/// — for undated items whose text named a time already over when it arrived
/// ("call at 9 AM?" received at 1 PM) — what that time was, so it isn't
/// mistaken for something still to come. [withArrival] appends the arrival
/// time for dated items too (Ask Echo questions about what came in when).
String describeEntry(
  RawData e,
  RelevanceWindow window,
  DateTime now, {
  bool withArrival = false,
}) {
  final label = describeWhen(window, e.timestamp, now);
  if (window.explicit) {
    return withArrival ? '$label; ${_arrived(e.timestamp, now)}' : label;
  }
  final named = extractExplicitWindows('${e.sender} ${e.content}', e.timestamp);
  if (named.isEmpty) return label;
  return '$label; mentions ${describeWhen(named.last, e.timestamp, now)}, already over';
}

/// When a briefing item applies, resolved against [now], e.g.
/// "Tomorrow (Sat 27 Sep), 11:00 AM", "Today (Fri 26 Sep), 5:00 PM to 5:30 PM",
/// "Fri 12 Dec to Mon 15 Dec", or for undated items "arrived today at 9:14 PM".
String describeWhen(RelevanceWindow window, DateTime receivedAt, DateTime now) {
  if (!window.explicit) return _arrived(receivedAt, now);
  final firstDay = startOfDay(window.start);
  final lastDay = startOfDay(
    window.hasTime ? window.start : window.end,
  );
  final days = firstDay == lastDay
      ? _dayLabel(firstDay, now)
      : '${_dayLabel(firstDay, now)} to ${_dayLabel(lastDay, now)}';
  if (!window.hasTime) return days;
  final sameDay = startOfDay(window.end) == firstDay;
  final times = !window.hasEndTime
      ? _clock(window.start)
      : '${_clock(window.start)} to ${_clock(window.end)}'
          '${sameDay ? '' : ' (${shortDate(window.end)})'}';
  return '$days, $times';
}

String _arrived(DateTime receivedAt, DateTime now) {
  final day = _relativeDay(receivedAt, now);
  final phrase = day == shortDate(receivedAt) ? 'on $day' : day.toLowerCase();
  return 'arrived $phrase at ${_clock(receivedAt)}';
}

String _dayLabel(DateTime day, DateTime now) {
  final relative = _relativeDay(day, now);
  final short = shortDate(day);
  return relative == short ? short : '$relative ($short)';
}

String _relativeDay(DateTime day, DateTime now) {
  // Hours / 24, rounded, tolerates DST-shortened or lengthened days.
  final hours = startOfDay(day).difference(startOfDay(now)).inHours;
  return switch ((hours / 24).round()) {
    0 => 'Today',
    1 => 'Tomorrow',
    -1 => 'Yesterday',
    _ => shortDate(day),
  };
}

String _clock(DateTime t) {
  final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final minute = t.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${t.hour < 12 ? 'AM' : 'PM'}';
}
