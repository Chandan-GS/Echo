import 'package:project_echo/features/echo/data/context/addressed.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/relevance/temporal_relevance.dart';
import 'package:project_echo/features/vault/data/app_access.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What Ask Echo opens with: the chat messages meant for the owner since they
/// last looked, and how much group chatter they can skip.
class ForYou {
  /// The last time Ask Echo was opened, or the start of today.
  final DateTime since;

  /// True when [since] is a real last look rather than the start of the day.
  final bool sinceLastLook;

  /// Newest first, the latest from each chat.
  final List<RawData> items;

  /// How many chats [items] came from in total (only a few are shown).
  final int chats;

  /// Group messages that weren't for the owner, and the busiest such group.
  final int chatter;
  final String? busiestGroup;

  const ForYou({
    required this.since,
    required this.sinceLastLook,
    required this.items,
    required this.chats,
    required this.chatter,
    required this.busiestGroup,
  });

  bool get isEmpty => items.isEmpty;

  static const _lastLookKey = 'ask_last_look_v1';
  static const shown = 3;

  static Future<ForYou> load(DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_lastLookKey);
    final lastLook = last == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(last);
    final since = lastLook != null && lastLook.isAfter(startOfDay(now))
        ? lastLook
        : startOfDay(now);
    final entries = await withoutExcludedSources(
      await IsarDataSource.getAllEntries(),
    );
    return summarise(entries, since, sinceLastLook: since == lastLook);
  }

  static Future<void> markLooked(DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastLookKey, now.millisecondsSinceEpoch);
  }

  /// The pure part of [load].
  static ForYou summarise(
    Iterable<RawData> entries,
    DateTime since, {
    bool sinceLastLook = false,
  }) {
    final fresh = entries.where((e) => e.timestamp.isAfter(since)).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final latestPerChat = <String, RawData>{};
    final chatter = <String, int>{};
    for (final e in fresh) {
      final addressed = Addressed.parse(e.addressed);
      if (addressed == null) continue;
      final chat = e.thread ?? e.sender;
      if (addressed == Addressed.group) {
        chatter[e.threadTitle ?? chat] =
            (chatter[e.threadTitle ?? chat] ?? 0) + 1;
      } else {
        latestPerChat.putIfAbsent(chat, () => e);
      }
    }
    final busiest = chatter.entries.isEmpty
        ? null
        : chatter.entries.reduce((a, b) => b.value > a.value ? b : a).key;
    return ForYou(
      since: since,
      sinceLastLook: sinceLastLook,
      items: latestPerChat.values.take(shown).toList(),
      chats: latestPerChat.length,
      chatter: chatter.values.fold(0, (a, b) => a + b),
      busiestGroup: busiest,
    );
  }
}

final _asks = RegExp(
  r"\?|\b(can you|could you|would you|will you|please|pls|need you|let me know|"
  r"don't forget|remember to|make sure|send|bring|call|confirm|reply|book|pay|"
  r"pick up|submit|fill)\b",
  caseSensitive: false,
);

/// Whether [e] holds something to do: it names a time, or asks something of
/// the owner. "lol" doesn't; "Call me when you're free" does.
bool looksActionable(RawData e) =>
    relevanceWindows('${e.sender} ${e.content}', e.timestamp).first.explicit ||
    _asks.hasMatch(e.content);
