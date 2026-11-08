import 'package:project_echo/features/echo/data/context/addressed.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/relevance/temporal_relevance.dart';
import 'package:project_echo/features/echo/data/waiting/wait_intent.dart';
import 'package:project_echo/features/todo/data/todo_planner.dart';

/// One group message, without the embedding, so a backlog can be read off
/// the main thread cheaply.
class GroupLine {
  final String key;
  final String sender;
  final String source;
  final String text;
  final DateTime at;
  final String? thread;
  final String title;
  final String? addressed;

  const GroupLine({
    required this.key,
    required this.sender,
    required this.source,
    required this.text,
    required this.at,
    required this.thread,
    required this.title,
    required this.addressed,
  });

  factory GroupLine.of(RawData e) => GroupLine(
    key: sourceKeyOf(e),
    sender: e.sender,
    source: e.source,
    text: e.content,
    at: e.timestamp,
    thread: e.thread,
    title: e.threadTitle ?? '',
    addressed: e.addressed,
  );

  RawData toEntry() => RawData()
    ..source = source
    ..sender = sender
    ..content = text
    ..timestamp = at
    ..thread = thread
    ..threadTitle = title
    ..isGroup = true
    ..addressed = addressed;
}

/// What's set aside as noise, in the order the page lists it.
enum SkipKind { goodMorning, forward, media, emoji, thanks }

String skipLabel(SkipKind k) => switch (k) {
  SkipKind.goodMorning => 'Good morning messages',
  SkipKind.forward => 'Forwarded messages',
  SkipKind.media => 'Stickers, photos and videos',
  SkipKind.emoji => 'Emoji-only replies',
  SkipKind.thanks => 'Thank-yous and okays',
};

String _skipNoun(SkipKind k) => switch (k) {
  SkipKind.goodMorning => 'good mornings',
  SkipKind.forward => 'forwards',
  SkipKind.media => 'stickers and photos',
  SkipKind.emoji => 'emoji replies',
  SkipKind.thanks => 'thank-yous',
};

final _greeting = RegExp(
  r'\b(?:g(?:oo|u)d\s*(?:mo?r?n\w*|mrng|afternoon|evening|eve|night|nite)|gm|gn|'
  r'su-?prabhat\w*|shubh\s*(?:prabhat|ratri|sandhya|dopahar)|shubhodaya|'
  r'jai\s+shri\s+\w+)\b'
  r'|सुप्रभात|शुभ\s*(?:प्रभात|रात्रि|संध्या)',
  caseSensitive: false,
  unicode: true,
);

/// How notification text labels something that isn't words.
final _media = RegExp(
  r'^(?:[^\p{L}\p{N}]*)'
  r'(?:sticker|gif|photo|image|video|audio|voice\s+(?:message|note|call)|'
  r'missed\s+(?:voice|video)?\s*call|document|contact|location|poll)'
  r'(?:\s*\(\d+\))?[^\p{L}\p{N}]*$',
  caseSensitive: false,
  unicode: true,
);

final _hasWord = RegExp(r'[\p{L}\p{N}]', unicode: true);
final _digit = RegExp(r'\d');

/// A greeting and little else: "Good morning, the meeting moved to 5" still
/// says something.
bool _isOnlyGreeting(String text) {
  final m = _greeting.firstMatch(text);
  if (m == null || text.length > 80 || _digit.hasMatch(text)) return false;
  final rest = text.replaceRange(m.start, m.end, ' ').trim();
  return rest.isEmpty || rest.split(RegExp(r'\s+')).length <= 4;
}

final _thanks = RegExp(
  r'^\W*(?:ok(?:ay)?|k+|thanks?|thank\s*you|thnx|ty|tysm|\+1|haan?|han|hmm+|'
  r'ji|acha|accha|theek\s*hai|done|noted|shukriya|dhanyavaad)\W*$',
  caseSensitive: false,
);

/// Why [text] is noise, or null when it says something.
SkipKind? skipKindOf(String text) {
  final t = text.trim();
  if (t.isEmpty || !_hasWord.hasMatch(t)) return SkipKind.emoji;
  final lower = t.toLowerCase();
  if (lower.startsWith('forwarded') || lower.startsWith('fwd:')) {
    return SkipKind.forward;
  }
  if (_media.hasMatch(t)) return SkipKind.media;
  if (_isOnlyGreeting(t)) return SkipKind.goodMorning;
  if (_thanks.hasMatch(t)) return SkipKind.thanks;
  return null;
}

final _amount = RegExp(
  r'₹\s*(\d[\d,]*(?:\.\d+)?)'
  r'|\b(?:rs\.?|inr)\s*(\d[\d,]*)'
  r'|\b(\d[\d,]*)\s*(?:rs\b|rupees\b|bucks\b|/-)',
  caseSensitive: false,
);

final _payApps = RegExp(
  r'\b(?:upi|gpay|google\s*pay|phone\s*pe|paytm|bhim)\b'
  r'|\b[\w.-]{2,}@(?:upi|ok\w+|ybl|paytm|ibl|axl|apl)\b',
  caseSensitive: false,
);

final _demand = RegExp(
  r'\b(?:send|pay|transfer|collect|deposit|contribute|owe[sd]?|due|'
  r'each|per\s+head|per\s+person|maintenance|bhej\w*|de\s*do|dedo|dena|dene|'
  r'jama|chahiye|sab\s*log|sabko|everyone)\b',
  caseSensitive: false,
);

final _alreadyDone = RegExp(
  r"\b(?:i\s+paid|i've\s+paid|ive\s+paid|have\s+paid|has\s+paid|already\s+paid|"
  r'paid\s+already|maine|kar\s+diya|kar\s+di|received|got\s+it|refunded)\b',
  caseSensitive: false,
);

/// A payment someone asked of the group.
class MoneyAsk {
  final GroupLine line;

  /// "₹850", or null when only a UPI handle or app was named.
  final String? amount;
  final DateTime? due;

  const MoneyAsk(this.line, this.amount, this.due);

  /// "₹850" or "a payment", for "Riya asked for ₹850".
  String get what => amount ?? 'a payment';
}

/// [line] as a money ask, or null if it's only money talk: someone saying
/// they paid isn't asking for anything.
MoneyAsk? moneyAskIn(GroupLine line) {
  final text = line.text;
  final amountMatch = _amount.firstMatch(text);
  if (amountMatch == null && !_payApps.hasMatch(text)) return null;
  if (!_demand.hasMatch(text) || _alreadyDone.hasMatch(text)) return null;
  String? amount;
  if (amountMatch != null) {
    final digits =
        amountMatch[1] ?? amountMatch[2] ?? amountMatch[3] ?? '';
    amount = '₹$digits';
  }
  DateTime? due;
  for (final w in extractExplicitWindows(text, line.at)) {
    if (w.explicit) {
      due = w.start;
      break;
    }
  }
  return MoneyAsk(line, amount, due);
}

/// A thing in the group the owner should act on.
class GroupNeed {
  final GroupLine line;
  final MoneyAsk? money;

  const GroupNeed(this.line, this.money);

  bool get isMoney => money != null;
}

/// A date someone named in the group that's still ahead.
class GroupDate {
  final DateTime when;
  final bool hasTime;
  final GroupLine line;

  const GroupDate(this.when, this.hasTime, this.line);
}

class SkipSummary {
  final Map<SkipKind, int> counts;
  final List<String> examples;

  const SkipSummary(this.counts, this.examples);

  int get total => counts.values.fold(0, (a, b) => a + b);

  /// "180 forwards, stickers and good mornings", the commonest first.
  String get label {
    final kinds = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final names = kinds.take(3).map((e) => _skipNoun(e.key)).toList();
    if (names.length == 1) return '$total ${names.single}';
    final head = names.sublist(0, names.length - 1).join(', ');
    return '$total $head and ${names.last}';
  }
}

class GroupDigest {
  final List<GroupNeed> needs;
  final List<GroupDate> dates;
  final SkipSummary skipped;

  /// Keys of the lines set aside, for "Show everything".
  final Set<String> skippedKeys;

  const GroupDigest({
    required this.needs,
    required this.dates,
    required this.skipped,
    required this.skippedKeys,
  });
}

const _needsShown = 8;
const _datesShown = 8;
const _examplesShown = 3;

/// Everything rules can tell about a group's messages, newest first in and
/// out. Runs without any model or network.
GroupDigest digestGroup(
  List<GroupLine> lines,
  Iterable<String> ownerNames,
  DateTime now, {
  Set<String> paid = const {},
}) {
  final counts = <SkipKind, int>{};
  final examples = <String>[];
  final skippedKeys = <String>{};
  final needs = <GroupNeed>[];
  final dates = <GroupDate>[];
  final seenDates = <String>{};
  for (final line in lines) {
    final kind = skipKindOf(line.text);
    if (kind != null) {
      counts[kind] = (counts[kind] ?? 0) + 1;
      skippedKeys.add(line.key);
      if (examples.length < _examplesShown &&
          kind != SkipKind.media &&
          kind != SkipKind.emoji) {
        examples.add(line.text.replaceAll('\n', ' '));
      }
      continue;
    }
    final money = moneyAskIn(line);
    if (money != null && !paid.contains(line.key)) {
      needs.add(GroupNeed(line, money));
    } else if (_namesOwner(line, ownerNames)) {
      final wait = classifyWait(
        line.text,
        isGroup: true,
        addressed: Addressed.mentioned.name,
      );
      if (wait.kind != WaitKind.ack &&
          wait.kind != WaitKind.closer &&
          wait.kind != WaitKind.code &&
          wait.kind != WaitKind.emojiOnly) {
        needs.add(GroupNeed(line, null));
      }
    }
    for (final w in extractExplicitWindows(line.text, line.at)) {
      if (!w.explicit || !w.start.isAfter(now)) continue;
      if (w.start.isAfter(now.add(const Duration(days: 90)))) continue;
      final id =
          '${dayKeyOf(w.start)}|${line.text.toLowerCase().trim().padRight(24).substring(0, 24)}';
      if (seenDates.add(id)) dates.add(GroupDate(w.start, w.hasTime, line));
      break;
    }
  }
  dates.sort((a, b) => a.when.compareTo(b.when));
  return GroupDigest(
    needs: needs.take(_needsShown).toList(),
    dates: dates.take(_datesShown).toList(),
    skipped: SkipSummary(counts, examples),
    skippedKeys: skippedKeys,
  );
}

bool _namesOwner(GroupLine line, Iterable<String> ownerNames) =>
    line.addressed == Addressed.mentioned.name ||
    mentionsAny(line.text, ownerNames);

String dayKeyOf(DateTime d) => '${d.year}-${d.month}-${d.day}';
