import 'dart:convert';

import 'package:project_echo/core/services/phone_actions.dart';
import 'package:project_echo/features/echo/data/context/chat_context_store.dart';
import 'package:project_echo/features/echo/data/home/home_feed.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/relevance/temporal_relevance.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/ask_parts.dart';
import 'package:project_echo/features/todo/data/todo_item.dart';
import 'package:project_echo/features/todo/data/todo_planner.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The pure parts of the desktop Today screen, kept apart so they can be
/// tested without a window.

enum TriageKind { waiting, promise, group }

/// One row of the triage list: a chat waiting on the owner, something they
/// said they'd do, or a busy group.
class TriageItem {
  final TriageKind kind;

  /// The message the row is about. For a promise, the owner's own words
  /// (sender "You"); for a group, its latest message.
  final RawData entry;
  final Promise? promise;
  final BusyGroup? group;

  const TriageItem._(this.kind, this.entry, {this.promise, this.group});

  TriageItem.waiting(RawData e) : this._(TriageKind.waiting, e);
  TriageItem.promise(Promise p)
    : this._(TriageKind.promise, p.entry, promise: p);
  TriageItem.group(BusyGroup g) : this._(TriageKind.group, g.latest, group: g);

  /// Stable across reloads, and the key reminders and to-dos use.
  String get id => switch (kind) {
    TriageKind.group => 'group:${group!.name}',
    _ => sourceKeyOf(entry),
  };

  String get heading => switch (kind) {
    TriageKind.waiting => 'Waiting on you',
    TriageKind.promise => 'You said you’d',
    TriageKind.group => 'Busy groups',
  };

  /// Who the reply goes to, or who the promise was made to.
  String get name => switch (kind) {
    TriageKind.waiting =>
      entry.sender.isEmpty ? (entry.threadTitle ?? entry.source) : entry.sender,
    TriageKind.promise => promise!.to,
    TriageKind.group => group!.name,
  };

  /// What follows the name: the group or the app ("College gang",
  /// "Slack"), "to Priya", or "41 new".
  String get where => switch (kind) {
    TriageKind.waiting =>
      entry.isGroup && (entry.threadTitle?.isNotEmpty ?? false)
          ? entry.threadTitle!
          : entry.source,
    TriageKind.promise => 'to ${promise!.to}',
    TriageKind.group => '${group!.count} new',
  };

  static List<TriageItem> fromFeed(HomeFeed feed) => [
    for (final e in feed.needsYou) TriageItem.waiting(e),
    for (final p in feed.promises) TriageItem.promise(p),
    for (final g in feed.busyGroups) TriageItem.group(g),
  ];
}

/// The chats the owner marked handled today, kept until the day is out.
class HandledMarks {
  HandledMarks._();

  static const key = 'desktop_handled_v1';

  static Future<Set<String>> load(DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    return decode(prefs.getString(key), now);
  }

  static Future<void> add(String id, DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    final kept = decode(prefs.getString(key), now)..add(id);
    await prefs.setString(
      key,
      jsonEncode({'day': dayKey(now), 'ids': kept.toList()}),
    );
  }

  /// Yesterday's marks don't count today.
  static Set<String> decode(String? raw, DateTime now) {
    try {
      final json = jsonDecode(raw ?? '{}') as Map;
      if (json['day'] != dayKey(now)) return {};
      return {for (final id in (json['ids'] as List? ?? const [])) '$id'};
    } catch (_) {
      return {};
    }
  }
}

/// One message of a chat, for reply suggestions.
class ChatLine {
  final String who;
  final String text;
  final DateTime at;
  final bool mine;

  /// The message the selected row is about.
  final bool picked;

  const ChatLine({
    required this.who,
    required this.text,
    required this.at,
    this.mine = false,
    this.picked = false,
  });
}

/// The chat around [picked]: what Echo kept of [entries] (the thread's
/// notifications) and the owner's own [turns] there, oldest first, at most
/// [max] of them and always including the picked one.
List<ChatLine> conversation(
  Iterable<RawData> entries,
  Iterable<MyTurn> turns, {
  required RawData picked,
  bool pickedMine = false,
  int max = 8,
}) {
  final pickedKey = sourceKeyOf(picked);
  final theirs = [
    for (final e in entries)
      ChatLine(
        who: e.sender.isEmpty ? e.source : e.sender,
        text: e.content,
        at: e.timestamp,
        mine: e.sender == 'You',
        picked: !pickedMine && sourceKeyOf(e) == pickedKey,
      ),
  ];
  // Some apps show the owner's messages in the notification too.
  bool shown(MyTurn t) => theirs.any(
    (l) =>
        l.mine && l.text == t.text && l.at.difference(t.at).inMinutes.abs() < 2,
  );
  final lines = [
    ...theirs,
    for (final t in turns)
      if (!shown(t))
        ChatLine(
          who: 'You',
          text: t.text,
          at: t.at,
          mine: true,
          picked:
              pickedMine &&
              t.at == picked.timestamp &&
              t.text == picked.content,
        ),
  ]..sort((a, b) => a.at.compareTo(b.at));
  if (!lines.any((l) => l.picked)) {
    lines
      ..add(
        ChatLine(
          who: pickedMine ? 'You' : picked.sender,
          text: picked.content,
          at: picked.timestamp,
          mine: pickedMine,
          picked: true,
        ),
      )
      ..sort((a, b) => a.at.compareTo(b.at));
  }
  if (lines.length <= max) return lines;
  final at = lines.indexWhere((l) => l.picked);
  var start = lines.length - max;
  if (at < start) start = at;
  return lines.sublist(start, start + max);
}

/// The latest reply sent from here to [entry]'s chat since it came in.
PhoneAction? replyTo(Iterable<PhoneAction> actions, RawData entry) {
  PhoneAction? latest;
  for (final a in actions) {
    if (a.kind != 'reply' || a.body['thread'] != entry.thread) continue;
    if (a.at.isBefore(entry.timestamp)) continue;
    if (latest == null || a.at.isAfter(latest.at)) latest = a;
  }
  return latest;
}

enum ReplyStage { going, slow, sent, ready, failed }

/// After this long without the phone, it's probably not on the same Wi-Fi.
const phoneSlow = Duration(seconds: 40);

/// How a reply sent from here is going, and the line that says so.
(ReplyStage, String) replyStatus(PhoneAction a, DateTime now) {
  final to = a.body['to']?.toString() ?? '';
  return switch (a.state) {
    ActionState.waiting || ActionState.collected =>
      now.difference(a.at) >= phoneSlow
          ? (
              ReplyStage.slow,
              'Waiting for your phone. Is it on the same Wi-Fi?',
            )
          : (ReplyStage.going, 'Sending through your phone…'),
    ActionState.done when a.outcome == 'sent' => (
      ReplyStage.sent,
      to.isEmpty
          ? 'Sent · ${clockLabel(a.at)}'
          : 'Sent to $to · ${clockLabel(a.at)}',
    ),
    ActionState.done => (
      ReplyStage.ready,
      'Ready on your phone: tap the notification to send',
    ),
    ActionState.failed => (ReplyStage.failed, 'Your phone couldn’t send it'),
  };
}

/// "Five people" + " are waiting on you", the first part in green.
(String, String) peopleWaiting(int n) {
  const words = [
    'No one',
    'One person',
    'Two people',
    'Three people',
    'Four people',
    'Five people',
    'Six people',
    'Seven people',
    'Eight people',
    'Nine people',
    'Ten people',
  ];
  final who = n < words.length ? words[n] : '$n people';
  return (who, n > 1 ? ' are waiting on you' : ' is waiting on you');
}

/// How long the briefing takes to say, at an easy speaking pace.
int briefingMinutes(String text) {
  final words = text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  return (words.length / 150).ceil().clamp(1, 99);
}

/// "You told Priya you’d share the photos tonight." from "I’ll share the
/// photos tonight"; quoted as said when it doesn't start that way.
String promiseLine(String to, String said) {
  final text = said.trim();
  final m = RegExp(
    r"^(i['’]?ll|i will|i['’]?m going to|i am going to)\s+(.+)$",
    caseSensitive: false,
  ).firstMatch(text);
  if (m == null) return 'You told $to: “$text”';
  final rest = m[2]!.replaceFirst(RegExp(r'[\s.!]+$'), '');
  return 'You told $to you’d $rest.';
}

/// One stop in "Rest of today".
class RailEvent {
  final DateTime at;
  final String label;
  final bool reminder;
  const RailEvent(this.at, this.label, {this.reminder = false});
}

/// Today's to-dos with a time and reminders still to come after [now],
/// in order. [reminders] are titles by time.
List<RailEvent> restOfToday(
  Iterable<TodoItem> todos,
  Iterable<(DateTime, String)> reminders,
  DateTime now,
) {
  final today = startOfDay(now);
  final tomorrow = DateTime(today.year, today.month, today.day + 1);
  bool later(DateTime t) => t.isAfter(now) && t.isBefore(tomorrow);
  return [
    for (final i in todos)
      if (!i.done && i.day == today && i.startsAt != null && later(i.startsAt!))
        RailEvent(i.startsAt!, i.title),
    for (final (at, title) in reminders)
      if (later(at)) RailEvent(at, 'Reminder · $title', reminder: true),
  ]..sort((a, b) => a.at.compareTo(b.at));
}

/// Reminder titles by key, from the store Reminders keeps.
Map<String, String> reminderTitles(String? raw) {
  try {
    return {
      for (final MapEntry(:key, :value)
          in (jsonDecode(raw ?? '{}') as Map).entries)
        if (value is Map && value['title'] is String)
          '$key': value['title'] as String,
    };
  } catch (_) {
    return {};
  }
}

/// "Saturday, 3 October".
String longDate(DateTime d) {
  const days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
}

String greetingAt(int hour) => switch (hour) {
  >= 5 && < 12 => 'Good morning',
  >= 12 && < 17 => 'Good afternoon',
  >= 17 && < 22 => 'Good evening',
  _ => 'Good night',
};

/// "2,045".
String withCommas(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
