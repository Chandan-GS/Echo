/// The evening wrap, written by plain rules so it works with nothing
/// downloaded: who's still waiting, how the to-dos went, who still owes the
/// owner an answer, and what tomorrow starts with.
class WrapWaiting {
  final String name;

  /// Whole days since they asked, by the calendar.
  final int days;
  const WrapWaiting(this.name, this.days);
}

class WrapOwed {
  final String name;
  final String what;
  final int days;
  const WrapOwed(this.name, this.what, this.days);
}

class WrapInput {
  final List<WrapWaiting> waiting;
  final int doneToday;
  final int totalToday;

  /// Titles of today's to-dos not done yet, in list order.
  final List<String> openToday;

  /// Tomorrow's list: the first item's title and time, and how many in all.
  final String? tomorrowFirst;
  final String? tomorrowTime;
  final int tomorrowCount;

  final List<WrapOwed> owed;

  /// Whether Echo has ever heard anything or held a to-do; false means a
  /// quiet day can't be told apart from an empty app.
  final bool hasAnyData;

  const WrapInput({
    this.waiting = const [],
    this.doneToday = 0,
    this.totalToday = 0,
    this.openToday = const [],
    this.tomorrowFirst,
    this.tomorrowTime,
    this.tomorrowCount = 0,
    this.owed = const [],
    this.hasAnyData = true,
  });
}

class EveningWrap {
  /// Sentences with **names** marked, as the briefing transcript expects.
  final List<String> sentences;

  /// Nothing to report tonight, whether a clear day or an empty app.
  final bool clear;

  /// Echo had nothing at all to go on.
  final bool noData;

  const EveningWrap({
    required this.sentences,
    this.clear = false,
    this.noData = false,
  });

  String get rawText => sentences.join(' ');
}

const _numberWords = [
  'Zero',
  'One',
  'Two',
  'Three',
  'Four',
  'Five',
  'Six',
  'Seven',
  'Eight',
  'Nine',
  'Ten',
  'Eleven',
  'Twelve',
];

String _count(int n) => n >= 0 && n < _numberWords.length
    ? _numberWords[n]
    : '$n';

String _countLower(int n) => n >= 0 && n < _numberWords.length
    ? _numberWords[n].toLowerCase()
    : '$n';

/// A name safe to put inside the transcript's ** markers.
String _bold(String name) => '**${name.replaceAll('*', '').trim()}**';

String _since(int days) => switch (days) {
  <= 0 => 'since today',
  1 => 'since yesterday',
  _ => 'for ${_countLower(days)} days',
};

EveningWrap buildEveningWrap(WrapInput i) {
  final waiting = [...i.waiting]..sort((a, b) => b.days.compareTo(a.days));
  final sentences = <String>["Here's your evening wrap."];

  switch (waiting.length) {
    case 0:
      if (i.totalToday > 0 || i.owed.isNotEmpty) {
        sentences.add('Nobody is waiting on you.');
      }
    case 1:
      final w = waiting.first;
      sentences.add('${_bold(w.name)} has been waiting ${_since(w.days)}.');
    case 2:
      final a = waiting[0], b = waiting[1];
      sentences.add(
        'Two people are still waiting: ${_bold(a.name)} ${_since(a.days)}, '
        'and ${_bold(b.name)} ${_since(b.days)}.',
      );
    default:
      final first = waiting.first;
      sentences.add(
        '${_count(waiting.length)} people are still waiting. '
        '${_bold(first.name)} has waited longest, ${_since(first.days)}.',
      );
  }

  if (i.totalToday > 0) {
    final open = i.openToday;
    if (open.isEmpty) {
      sentences.add(
        i.totalToday == 1
            ? 'You finished your to-do today.'
            : 'You finished all ${_countLower(i.totalToday)} to-dos today.',
      );
    } else if (i.doneToday == 0) {
      sentences.add(
        '${_count(open.length)} ${open.length == 1 ? 'to-do is' : 'to-dos are'} '
        'still open today, starting with ${open.first}.',
      );
    } else {
      sentences.add(
        'You finished ${_countLower(i.doneToday)} of '
        '${_countLower(i.totalToday)} to-dos today. Still open: ${open.first}.',
      );
    }
  }

  for (final o in i.owed.take(2)) {
    sentences.add('${_bold(o.name)} still owes you an answer about ${o.what}.');
  }

  if (i.tomorrowFirst case final first?) {
    final time = i.tomorrowTime;
    final more = i.tomorrowCount - 1;
    sentences.add(
      time != null
          ? 'Tomorrow starts with $first at $time.'
          : more > 0
          ? 'Tomorrow: $first, and ${_countLower(more)} more.'
          : 'Tomorrow: $first.',
    );
  } else if (sentences.length > 1) {
    sentences.add('Nothing on your list for tomorrow yet.');
  }

  final clear =
      waiting.isEmpty &&
      i.totalToday == 0 &&
      i.owed.isEmpty &&
      i.tomorrowFirst == null;

  if (clear) {
    if (!i.hasAnyData) {
      return const EveningWrap(
        sentences: [
          "Echo hasn't heard any of your messages yet, so there's nothing to "
              'wrap up tonight.',
        ],
        clear: true,
        noData: true,
      );
    }
    return const EveningWrap(
      sentences: [
        "A clear evening. Nobody's waiting on you, and tomorrow's list is "
            'empty. Sleep well.',
      ],
      clear: true,
    );
  }

  sentences.add("That's it. Sleep well.");
  return EveningWrap(sentences: sentences);
}

/// Asked-and-unanswered: the owner's latest message in a chat that wants
/// something back, older than a day, with nothing from that chat since.
List<WrapOwed> owedFromTurns({
  required Iterable<({String thread, DateTime at, String text})> turns,
  required Map<String, ({String name, DateTime lastHeard, bool isGroup})> threads,
  required bool Function(String text) asksSomething,
  required DateTime now,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final owed = <WrapOwed>[];
  for (final t in turns) {
    final thread = threads[t.thread];
    if (thread == null || thread.isGroup) continue;
    if (thread.lastHeard.isAfter(t.at)) continue;
    final day = DateTime(t.at.year, t.at.month, t.at.day);
    final days = today.difference(day).inDays;
    if (days < 1 || days > 14) continue;
    if (!asksSomething(t.text)) continue;
    owed.add(WrapOwed(thread.name, _shortened(t.text), days));
  }
  owed.sort((a, b) => b.days.compareTo(a.days));
  return owed;
}

String _shortened(String text) {
  final t = text.trim().replaceAll(RegExp(r'[?!.]+$'), '');
  return t.length <= 60 ? t : '${t.substring(0, 60).trimRight()}…';
}
