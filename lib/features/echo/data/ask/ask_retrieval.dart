import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/relevance/briefing_selection.dart';
import 'package:project_echo/features/echo/data/relevance/temporal_relevance.dart';

/// Which notifications an Ask Echo question is about. All local — MiniLM
/// similarity, keywords, and resolved time windows — so the LLM only ever sees
/// the handful of lines it needs.
class RankedNotification {
  final RawData entry;
  final double score;
  const RankedNotification(this.entry, this.score);
}

/// Words that never make a notification relevant on their own.
const _stopWords = {
  'notification', 'notifications', 'message', 'messages', 'email', 'emails',
  'app', 'from', 'about', 'summarize', 'summarise', 'what', 'did', 'say',
  'the', 'tell', 'me', 'any', 'update', 'updates', 'show', 'get', 'give',
  'have', 'has', 'was', 'were', 'are', 'there', 'anything', 'something',
  'who', 'when', 'where', 'which', 'you', 'your', 'mine', 'for', 'and',
  'came', 'come', 'got', 'received', 'happened', 'happening', 'new',
  'latest', 'recent', 'do', 'doing', 'need', 'all', 'my',
};

/// Time words are handled through relevance windows, not keywords: "tomorrow"
/// in a notification from yesterday means today, so matching the literal word
/// would surface the wrong things.
const _temporalWords = {
  'today', 'tomorrow', 'tonight', 'yesterday', 'tmrw', 'tmr', 'morning',
  'afternoon', 'evening', 'night', 'week', 'weekend', 'day', 'days',
  'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday',
  'sunday', 'upcoming', 'coming', 'next', 'schedule', 'plan', 'plans',
  'agenda', 'pending', 'later', 'soon', 'time',
};

/// "What's coming up?" names no date but still means from now onwards.
final _upcomingPattern = RegExp(
  r"\b(upcoming|coming up|what'?s next|next up|my (schedule|agenda|plans?|day)|"
  r'pending|later today|anything planned)\b',
  caseSensitive: false,
);

/// "What came in yesterday?" is about when things ARRIVED; "what's on
/// today?" is about when things HAPPEN.
final _arrivalPattern = RegExp(
  r'\b(came|come|received|got|get|sent|arrived|messages?|notifications?|'
  r'texts?|emails?|mails?|said|say|says|told|wrote|pinged)\b',
  caseSensitive: false,
);

bool isArrivalQuestion(String question) => _arrivalPattern.hasMatch(question);

/// The time span a question asks about, if any: explicit ("tomorrow", "on
/// Monday", "yesterday") or implied ("what's coming up?" → now until the end
/// of tomorrow). Empty when the question isn't about a time.
List<RelevanceWindow> questionWindows(String question, DateTime now) {
  final explicit = extractExplicitWindows(question, now, rollPastTimes: false);
  if (explicit.isNotEmpty) return explicit;
  if (_upcomingPattern.hasMatch(question)) {
    return [
      RelevanceWindow(
        start: now,
        end: briefingHorizonEnd(now),
        explicit: true,
        hasTime: false,
      ),
    ];
  }
  return const [];
}

const _metaBoost = 0.4;
const _contentBoost = 0.35;
const _weatherBoost = 0.5;
const _carryBoost = 0.25;
const _timeMatchBoost = 0.5;
const _arrivedBoost = 0.2;
// A question that's only about a time ("what came in yesterday?") has nothing
// else to match on, so arriving in that window has to be enough on its own.
const _arrivedBoostTimeOnly = 0.35;
const _timeMismatchPenalty = 0.3;

/// Scores every notification against [question] and returns the best ones.
///
/// [questionEmbedding] is the (possibly follow-up-blended) MiniLM vector; null
/// on desktop, where only keywords and time count. [carriedIds] are the
/// previous answer's sources, nudged up so a follow-up ("what time was
/// that?") keeps talking about the same things.
List<RankedNotification> rankForQuestion({
  required String question,
  required DateTime now,
  required Iterable<RawData> entries,
  List<double>? questionEmbedding,
  Set<int> carriedIds = const {},
  int limit = 10,
  double threshold = 0.30,
}) {
  final words = _words(question)
      .where((w) => w.length > 2 && !_temporalWords.contains(w))
      .toSet();
  final asksWeather = words.any(_weatherQueryWords.contains);
  final timeWindows = questionWindows(question, now);
  final asksArrivals = isArrivalQuestion(question);

  final scored = <RankedNotification>[];
  for (final e in entries) {
    var score = cosineSimilarity(questionEmbedding, e.embedding);

    final meta = {..._words(e.sender), ..._words(e.source)};
    if (words.any(meta.contains)) score += _metaBoost;

    final contentLower = e.content.toLowerCase();
    if (words.any(_words(contentLower).contains)) score += _contentBoost;

    // A weather alert's sender is just "Google" and its text "29° in
    // Bengaluru · Mostly cloudy" — no literal overlap with "what's the
    // weather like", so match the intent instead.
    if (asksWeather && _looksLikeWeather(contentLower)) score += _weatherBoost;

    if (carriedIds.contains(e.id)) score += _carryBoost;

    if (timeWindows.isNotEmpty) {
      score += _timeScore(
        e,
        timeWindows,
        timeOnly: words.isEmpty,
        asksArrivals: asksArrivals,
      );
    }

    scored.add(RankedNotification(e, score));
  }

  scored.sort((a, b) => b.score.compareTo(a.score));
  final seen = <String>{};
  final result = <RankedNotification>[];
  for (final s in scored) {
    if (s.score < threshold) break;
    if (!seen.add(s.entry.content.toLowerCase().trim())) continue;
    result.add(s);
    if (result.length >= limit) break;
  }
  return result;
}

/// Strong match when the notification is ABOUT the asked time; weaker when it
/// arrived then (counted for dated notifications only when the question is
/// about arrivals — "what's on today?" shouldn't surface today's message about
/// tomorrow); neutral when it's undated but still current; a penalty when it's
/// about some other time entirely.
double _timeScore(
  RawData e,
  List<RelevanceWindow> asked, {
  required bool timeOnly,
  required bool asksArrivals,
}) {
  final windows = relevanceWindows('${e.sender} ${e.content}', e.timestamp);
  bool overlaps(RelevanceWindow w) =>
      asked.any((a) => w.overlaps(a.start, a.end));

  if (windows.any((w) => w.explicit && overlaps(w))) return _timeMatchBoost;
  final arrivedInWindow = asked.any(
    (a) => !e.timestamp.isBefore(a.start) && !e.timestamp.isAfter(a.end),
  );
  final dated = windows.any((w) => w.explicit);
  if (arrivedInWindow && (asksArrivals || !dated)) {
    return timeOnly ? _arrivedBoostTimeOnly : _arrivedBoost;
  }
  if (windows.any((w) => !w.explicit && overlaps(w))) return 0;
  return -_timeMismatchPenalty;
}

/// How a notification is presented to the model: its most relevant window,
/// resolved against [now], e.g. "[Tomorrow (Sun 27 Sep), 11:00 AM]" or
/// "[Today (Sat 26 Sep), 10:30 AM, already over]". [withArrival] adds when it
/// arrived, for questions about what came in when.
String askTimeLabel(RawData e, DateTime now, {bool withArrival = false}) {
  final windows = relevanceWindows('${e.sender} ${e.content}', e.timestamp);
  final current = windows.where((w) => !w.end.isBefore(now));
  final window = current.isNotEmpty ? current.first : windows.last;
  final over = window.explicit && window.end.isBefore(now);
  final label = describeEntry(e, window, now, withArrival: withArrival);
  if (!over) return label;
  // "…, 10:30 AM, already over" — before any "; arrived …" suffix.
  final split = label.indexOf('; ');
  return split < 0
      ? '$label, already over'
      : '${label.substring(0, split)}, already over${label.substring(split)}';
}

Iterable<String> _words(String s) => s
    .toLowerCase()
    .split(RegExp(r'\W+'))
    .where((w) => w.isNotEmpty && !_stopWords.contains(w));

const _weatherQueryWords = {
  'weather', 'forecast', 'temperature', 'rain', 'raining', 'rainy', 'sunny',
  'cloudy', 'climate', 'hot', 'cold', 'humid', 'humidity', 'storm', 'wind',
  'windy', 'snow', 'snowing',
};

final _degreePattern = RegExp(r'\d+\s*°');
const _weatherContentMarkers = [
  'cloudy', 'forecast', 'rain', 'sunny', 'humidity', 'storm', 'clear sky',
  'overcast',
];

bool _looksLikeWeather(String contentLower) =>
    _degreePattern.hasMatch(contentLower) ||
    _weatherContentMarkers.any(contentLower.contains);

/// Casual openers/closers that never need notification context — matched as
/// the whole message so a real question containing one of these words still
/// gets normal retrieval.
final _smallTalkPattern = RegExp(
  r"^(hi+|hey+|hello+|yo|sup|what'?s up|"
  r'good\s*(morning|afternoon|evening|night)|'
  r"how('?s| is| are) it going|how are you( doing)?|"
  r'thanks?( you)?|thx|ty|'
  r'ok(ay)?|cool|nice|great|got it|sounds good|'
  r'bye|goodbye|see (you|ya)|good ?night)[\s!.?]*$',
  caseSensitive: false,
);

bool isSmallTalk(String text) => _smallTalkPattern.hasMatch(text.trim());
