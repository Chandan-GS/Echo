import 'dart:math' as math;

import 'package:project_echo/features/echo/data/context/addressed.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/relevance/temporal_relevance.dart';

/// A notification chosen for the briefing, with the window that got it in.
class BriefingItem {
  final RawData entry;
  final RelevanceWindow window;
  const BriefingItem(this.entry, this.window);
}

/// Senders and phrases that are never briefing material (promos, OTPs,
/// transactional noise). Matched as whole words, so "Hubert" isn't Uber and
/// "Footprint" holds no OTP.
///
/// Sender names only rule out apps and businesses: a chat contact (anything
/// with an [Addressed] value) is a person, whatever they're called.
const _junkSenders = [
  'zomato',
  'swiggy',
  'myntra',
  'lenskart',
  'amazon',
  'uber',
  'hdfc',
  'credit card',
  'makemytrip',
  'apollo',
  'dominos',
  'jio',
  'urban company',
  'blinkit',
  'flipkart',
  'quora',
  'linkedin',
  'medium',
];

/// Phrases that mark junk whoever sent them.
const _junkKeywords = ['% off', 'otp', 'flash sale'];

/// Promo words that only mark junk from an app or business: "Are you free at
/// 5?" from a friend is a question, "Free delivery" from a shop is an ad.
const _promoKeywords = ['discount', 'free'];

final _junkSenderPattern = _wholeWords(_junkSenders);
final _junkKeywordPattern = _wholeWords(_junkKeywords);
final _promoKeywordPattern = _wholeWords(_promoKeywords);

/// Any of [phrases] as a whole word, not inside a longer one. A phrase that
/// starts or ends with a symbol ("% off") needs no boundary on that side, so
/// "20% off" still matches.
RegExp _wholeWords(List<String> phrases) {
  final letter = RegExp(r'[\p{L}\p{N}]', unicode: true);
  const before = r'(?<![\p{L}\p{N}])', after = r'(?![\p{L}\p{N}])';
  final alternatives = [
    for (final p in phrases)
      '${letter.hasMatch(p[0]) ? before : ''}${RegExp.escape(p)}'
          '${letter.hasMatch(p[p.length - 1]) ? after : ''}',
  ];
  return RegExp(alternatives.join('|'), caseSensitive: false, unicode: true);
}

/// Whether [e] is promo or transactional noise rather than something for the
/// owner to know about.
bool isJunk(RawData e) {
  if (_junkKeywordPattern.hasMatch(e.content)) return true;
  // A chat contact is a person: their name and casual words don't count.
  if (e.addressed != null) return false;
  return _junkSenderPattern.hasMatch(e.sender) ||
      _promoKeywordPattern.hasMatch(e.content);
}

/// A busy group can't crowd out everything else: of its messages that aren't
/// aimed at the owner and name no date or time, only the latest few are
/// considered.
const groupChatterPerThread = 3;

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
/// notifications carry no embeddings) decides. Chat messages aimed at the
/// owner count for more and group chatter for less, and [affinity] (how often
/// the owner opens rather than swipes away a thread, −1 to 1) nudges the
/// rest. What's kept is returned dated first, chronologically, then undated
/// by importance.
List<BriefingItem> selectForBriefing(
  Iterable<RawData> entries,
  DateTime now, {
  Map<String, String> aliases = const {},
  List<String> blockedCategories = const [],
  List<double>? priorityVector,
  double Function(String? thread)? affinity,
  int limit = 15,
}) {
  final horizonEnd = briefingHorizonEnd(now);

  // Latest copy of each message wins: the same words from the same sender in
  // the same conversation. Rahul's "Call me" and Mom's are two messages.
  final unique = <String, RawData>{};
  final sorted = entries.toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  for (final e in sorted) {
    if (blockedCategories.contains(displaySource(e.source, aliases))) continue;
    if (isJunk(e)) continue;
    unique['${e.sender}|${e.thread ?? ''}|${e.content}'] = e;
  }

  // Group chatter is capped, newest first, but a message naming a date or
  // time is never cut for it ("Bus leaves 6 AM Saturday" before a string of
  // "ok 👍") and doesn't use up the group's share.
  final chatter = <String, int>{};
  final pool = unique.values.toList()
    ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  pool.retainWhere((e) {
    if (e.thread == null || Addressed.parse(e.addressed) != Addressed.group) {
      return true;
    }
    final named = extractExplicitWindows(
      '${e.sender} ${e.content}',
      e.timestamp,
    );
    if (named.isNotEmpty) return true;
    final n = chatter.update(e.thread!, (v) => v + 1, ifAbsent: () => 1);
    return n <= groupChatterPerThread;
  });

  final dated = <BriefingItem>[];
  final undated = <BriefingItem>[];
  for (final e in pool) {
    final windows = relevanceWindows('${e.sender} ${e.content}', e.timestamp);
    final inHorizon = windows.where((w) => w.overlaps(now, horizonEnd));
    if (inHorizon.isEmpty) continue;
    final window = inHorizon.first; // windows are sorted by start
    (window.explicit ? dated : undated).add(BriefingItem(e, window));
  }

  // Importance for the cap: a named date/time is a strong signal on its own.
  final importance = <BriefingItem, double>{
    for (final i in [...dated, ...undated])
      i:
          (i.window.explicit ? 1.0 : 0.0) +
          (priorityVector != null
              ? cosineSimilarity(priorityVector, i.entry.embedding)
              : i.entry.timestamp.millisecondsSinceEpoch / 1e15) +
          (Addressed.parse(i.entry.addressed)?.weight ?? 0) +
          0.3 * (affinity?.call(i.entry.thread) ?? 0),
  };
  final kept =
      ([...dated, ...undated]
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
bool isStillRelevant(RawData entry, DateTime now) => relevanceWindows(
  '${entry.sender} ${entry.content}',
  entry.timestamp,
).any((w) => !w.end.isBefore(now));

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
  final lastDay = startOfDay(window.hasTime ? window.start : window.end);
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
