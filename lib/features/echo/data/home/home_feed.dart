import 'package:project_echo/features/echo/data/context/addressed.dart';
import 'package:project_echo/features/echo/data/context/chat_context_store.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/relevance/temporal_relevance.dart';
import 'package:project_echo/features/todo/data/todo_planner.dart';
import 'package:project_echo/features/todo/data/todo_store.dart';
import 'package:project_echo/features/vault/data/app_access.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What Home shows under the briefing, from today's messages: the chats
/// waiting on the owner, what the owner said they'd do, and the groups that
/// were busy without them.
class HomeFeed {
  /// The latest message from each chat that wants the owner and that they
  /// haven't answered since, newest first.
  final List<RawData> needsYou;

  /// Things the owner told someone they'd do, with a time, not yet on the
  /// list or done.
  final List<Promise> promises;

  /// Groups with the most messages not meant for the owner.
  final List<BusyGroup> busyGroups;

  const HomeFeed({
    this.needsYou = const [],
    this.promises = const [],
    this.busyGroups = const [],
  });

  static const empty = HomeFeed();

  static const needsYouShown = 3;
  static const promisesShown = 2;
  static const groupsShown = 3;

  /// A group needs this many messages today to count as busy.
  static const busyAt = 5;

  static const _doneKey = 'home_promises_done_v1';

  static Future<HomeFeed> load(DateTime now) async {
    final entries = await withoutExcludedSources(
      await IsarDataSource.getAllEntries(),
    );
    final (todos, _) = await TodoStore().load();
    final prefs = await SharedPreferences.getInstance();
    return summarise(
      entries,
      await ChatContextStore.loadMyTurns(),
      now,
      skip: {
        for (final t in todos) t.sourceKey,
        ...?prefs.getStringList(_doneKey),
      },
    );
  }

  /// "Did it": the promise isn't brought up again.
  static Future<void> markDone(Promise p) async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getStringList(_doneKey) ?? const [];
    await prefs.setStringList(_doneKey, [
      ...done.skip(done.length > 50 ? done.length - 50 : 0),
      p.key,
    ]);
  }

  /// The pure part of [load]. [skip] holds the source keys of promises
  /// already on the list or done.
  static HomeFeed summarise(
    Iterable<RawData> entries,
    MyTurns turns,
    DateTime now, {
    Set<String> skip = const {},
  }) {
    final today = startOfDay(now);
    final fresh =
        entries
            .where(
              (e) => !e.timestamp.isBefore(today) && !e.timestamp.isAfter(now),
            )
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final waiting = <String, RawData>{};
    final answered = <String>{};
    final groups = <String, List<RawData>>{};
    final chats = <String, RawData>{};
    for (final e in fresh) {
      if (e.thread != null) chats.putIfAbsent(e.thread!, () => e);
      final addressed = Addressed.parse(e.addressed);
      if (addressed == null) continue;
      if (addressed == Addressed.group) {
        final name = e.threadTitle;
        if (name != null && name.isNotEmpty) {
          (groups[name] ??= []).add(e);
        }
        continue;
      }
      // Only a chat's newest message counts; once the owner has written in
      // the chat after it, the chat isn't waiting.
      final chat = e.thread ?? e.sender;
      if (waiting.containsKey(chat) || answered.contains(chat)) continue;
      final mine = turns.lastBefore(e.thread, now);
      if (mine != null && mine.at.isAfter(e.timestamp)) {
        answered.add(chat);
      } else {
        waiting[chat] = e;
      }
    }

    final promises = <Promise>[];
    for (final MapEntry(key: thread, value: list) in turns.byThread.entries) {
      final chat = chats[thread];
      if (chat == null) continue; // nothing to say who it was to
      for (final t in list) {
        if (t.at.isBefore(today) || t.at.isAfter(now)) continue;
        if (!_promise.hasMatch(t.text)) continue;
        if (!relevanceWindows(t.text, t.at).first.explicit) continue;
        final p = Promise(chat: chat, turn: t);
        if (!skip.contains(p.key)) promises.add(p);
      }
    }
    promises.sort((a, b) => b.turn.at.compareTo(a.turn.at));

    final busy =
        [
          for (final MapEntry(key: name, value: list) in groups.entries)
            if (list.length >= busyAt)
              BusyGroup(name: name, count: list.length, latest: list.first),
        ]..sort((a, b) {
          final byCount = b.count.compareTo(a.count);
          return byCount != 0
              ? byCount
              : b.latest.timestamp.compareTo(a.latest.timestamp);
        });

    return HomeFeed(
      needsYou: waiting.values.toList(),
      promises: promises.take(promisesShown).toList(),
      busyGroups: busy.take(groupsShown).toList(),
    );
  }
}

/// "I'll send it by 5", "will do tonight", "let me call you at 9".
/// Phones type either apostrophe.
final _promise = RegExp(
  r"\b(i['’]?ll|i will|i['’]?m going to|i am going to|i['’]?m gonna|"
  r"will do|let me|i shall|i can do)\b",
  caseSensitive: false,
);

/// Something the owner told a chat they'd do.
class Promise {
  /// The latest message from that chat, for its name and app.
  final RawData chat;
  final MyTurn turn;

  const Promise({required this.chat, required this.turn});

  /// Who it was said to: the group, or the person.
  String get to =>
      (chat.threadTitle?.isNotEmpty ?? false) ? chat.threadTitle! : chat.sender;

  /// The promise as a message, for the to-do list and reminders.
  RawData get entry => RawData()
    ..source = chat.source
    ..sender = 'You'
    ..content = turn.text
    ..timestamp = turn.at
    ..thread = chat.thread
    ..threadTitle = to
    ..isGroup = chat.isGroup;

  String get key => sourceKeyOf(entry);
}

/// A group that was busy today without the owner.
class BusyGroup {
  final String name;
  final int count;

  /// Its newest message.
  final RawData latest;

  const BusyGroup({
    required this.name,
    required this.count,
    required this.latest,
  });
}
