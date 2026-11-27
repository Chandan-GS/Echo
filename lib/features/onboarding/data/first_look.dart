import 'package:project_echo/features/echo/data/context/addressed.dart';
import 'package:project_echo/features/echo/data/context/chat_context_store.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/relevance/briefing_selection.dart';
import 'package:project_echo/features/echo/data/relevance/temporal_relevance.dart';

/// How full the phone was when Echo first looked. Sent with the onboarding
/// funnel's "first look heard" event, so it carries no content.
enum FirstLookKind {
  /// Nothing worth reading: an empty shade, or only offers and codes.
  empty,
  normal,

  /// At least [busyFirstLook] notifications.
  busy,
}

/// From this many notifications on, the first look calls the day busy.
const busyFirstLook = 30;

/// A short spoken first look at what's already on the phone, read out in
/// onboarding the moment notification access is granted. It's built from
/// what was caught up from the shade, without a model, so it's instant and
/// works before any engine is set up.
class FirstLook {
  /// What Echo says: three to five sentences.
  final String text;
  final FirstLookKind kind;

  /// Notifications counted (not calendar events, offers or codes).
  final int notifications;

  /// The apps they came from.
  final int apps;

  /// People with a message for the owner they haven't answered, newest
  /// first.
  final List<String> waiting;

  /// Calendar events and notifications with a time today or tomorrow.
  final int comingUp;

  const FirstLook({
    required this.text,
    required this.kind,
    required this.notifications,
    required this.apps,
    required this.waiting,
    required this.comingUp,
  });
}

/// Builds the first look at [now] from [entries] (what's saved so far).
///
/// It counts the last day's notifications and the apps they came from, sets
/// offers and codes aside ([isJunk]), names who's waiting to hear back
/// (a chat aimed at the owner — [Addressed] — that they haven't answered
/// since, going by [myTurns]), and picks the first thing with a time today
/// or tomorrow, the way the briefing does ([selectForBriefing]). [name] is
/// the owner's, when they've given it; [briefingTime] ("HH:mm") is when the
/// first full briefing comes. Sources in [excluded] (after [aliases]) are
/// left out, as in the briefing.
FirstLook buildFirstLook({
  required Iterable<RawData> entries,
  required DateTime now,
  String? name,
  MyTurns myTurns = const MyTurns({}),
  Map<String, String> aliases = const {},
  Set<String> excluded = const {},
  String briefingTime = '07:00',
}) {
  final since = now.subtract(const Duration(days: 1));
  final recent = [
    for (final e in entries)
      if (e.timestamp.isAfter(since) &&
          !excluded.contains(displaySource(e.source, aliases)))
        e,
  ];
  bool isCalendar(RawData e) => e.source == 'Calendar' && e.thread == null;

  final notifications = [
    for (final e in recent)
      if (!isCalendar(e) && !e.timestamp.isAfter(now) && !isJunk(e)) e,
  ];
  final junk = recent.where((e) => !isCalendar(e) && isJunk(e)).length;
  final apps = {
    for (final e in notifications) displaySource(e.source, aliases),
  };

  // Who's waiting: one name per conversation, newest first, unless the
  // owner has written there since.
  final waiting = <String>[];
  final threads = <String>{};
  final newestFirst = [...notifications]
    ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  for (final e in newestFirst) {
    final to = Addressed.parse(e.addressed);
    if (to == null || to == Addressed.group) continue;
    final thread = e.thread, who = e.sender.trim();
    if (thread == null || who.isEmpty || !threads.add(thread)) continue;
    final answered = myTurns.lastBefore(thread, now);
    if (answered != null && !answered.at.isBefore(e.timestamp)) continue;
    if (!waiting.contains(who)) waiting.add(who);
  }

  // What has a time today or tomorrow and isn't over, soonest first.
  final comingUp =
      selectForBriefing(
            recent.where((e) => isCalendar(e) || !e.timestamp.isAfter(now)),
            now,
            aliases: aliases,
          )
          .where((i) => i.window.explicit && !i.window.end.isBefore(now))
          .toList()
        ..sort((a, b) => a.window.start.compareTo(b.window.start));

  final hello = name == null || name.trim().isEmpty
      ? 'Hi'
      : 'Hi ${name.trim().split(RegExp(r'\s+')).first}';
  final next = _nextBriefing(briefingTime, now);
  final kind = notifications.isEmpty && comingUp.isEmpty
      ? FirstLookKind.empty
      : notifications.length >= busyFirstLook
      ? FirstLookKind.busy
      : FirstLookKind.normal;

  final sentences = <String>[];
  if (kind == FirstLookKind.empty) {
    sentences
      ..add(
        junk > 0
            ? '$hello, your phone only has offers and codes on it right now, '
                  'nothing you need to act on.'
            : '$hello, your phone is nice and quiet right now, so there’s '
                  'nothing for me to read you yet.',
      )
      ..add('From now on I’ll listen as things come in.')
      ..add(
        '$next, I’ll tell you who’s waiting on you and what’s coming up, '
        'so you don’t have to scroll through a thing.',
      );
  } else {
    sentences.add('$hello, here’s a first look at what’s on your phone.');
    if (notifications.isNotEmpty) {
      final n = _count(notifications.length, 'notification');
      final from = apps.length == 1 ? apps.first : '${apps.length} apps';
      final aside = junk > 0
          ? ', and I’ve set aside ${_count(junk, 'offer or code', 'offers and codes')}'
          : '';
      sentences.add(
        kind == FirstLookKind.busy
            ? 'It’s a busy one: $n from $from$aside.'
            : 'There ${notifications.length == 1 ? 'is' : 'are'} $n from '
                  '$from$aside.',
      );
    }
    if (waiting.isNotEmpty) {
      final also = waiting.length - 2;
      final names = switch (waiting.length) {
        1 => '${waiting[0]} is',
        2 => '${waiting[0]} and ${waiting[1]} are',
        _ => '${waiting[0]}, ${waiting[1]} and ${_count(also, 'other')} are',
      };
      sentences.add('$names waiting to hear back from you.');
    }
    if (comingUp.isNotEmpty) {
      final first = comingUp.first;
      final more = comingUp.length - 1;
      sentences.add(
        'Coming up: ${_thing(first.entry, aliases)}, '
        '${_when(first.window, now)}'
        '${more > 0 ? ', and ${_count(more, 'more thing')} today or tomorrow' : ''}.',
      );
    }
    sentences.add(
      '$next, I’ll read you all of it like this, so you never have to '
      'scroll.',
    );
  }

  return FirstLook(
    text: sentences.take(5).join(' '),
    kind: kind,
    notifications: notifications.length,
    apps: apps.length,
    waiting: waiting,
    comingUp: comingUp.length,
  );
}

/// "3 notifications", "1 notification".
String _count(int n, String one, [String? many]) =>
    '$n ${n == 1 ? one : (many ?? '${one}s')}';

/// What [e] is called when read out: a calendar event by its title, a chat
/// by who wrote it, anything else by its app.
String _thing(RawData e, Map<String, String> aliases) {
  if (e.source == 'Calendar' && e.thread == null) return e.sender.trim();
  if (e.addressed != null && e.sender.trim().isNotEmpty) {
    return 'a message from ${e.who}';
  }
  return 'something from ${displaySource(e.source, aliases)}';
}

/// "today at 5 PM", "tomorrow", "under way now".
String _when(RelevanceWindow w, DateTime now) {
  if (w.start.isBefore(now)) return w.hasTime ? 'under way now' : 'today';
  final day = startOfDay(w.start) == startOfDay(now) ? 'today' : 'tomorrow';
  return w.hasTime ? '$day at ${spokenClock(w.start)}' : day;
}

/// A time as Echo says it: "7 AM", "5:30 PM".
String spokenClock(DateTime t) {
  final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final minutes = t.minute == 0
      ? ''
      : ':${t.minute.toString().padLeft(2, '0')}';
  return '$hour$minutes ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// "Tomorrow at 7 AM", or "Today at 7 AM" when it's still ahead today.
String _nextBriefing(String hhmm, DateTime now) {
  final parts = hhmm.split(':');
  final h = int.tryParse(parts.first) ?? 7;
  final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  final today = DateTime(now.year, now.month, now.day, h, m);
  final at = spokenClock(today);
  return today.isAfter(now) ? 'Today at $at' : 'Tomorrow at $at';
}
