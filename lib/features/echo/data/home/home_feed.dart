import 'package:project_echo/features/echo/data/context/addressed.dart';
import 'package:project_echo/features/echo/data/context/chat_context_store.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/relevance/temporal_relevance.dart';
import 'package:project_echo/features/echo/data/waiting/wait_intent.dart';
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

  /// Every group busy today, muted or not, busiest first.
  final List<BusyGroup> allGroups;

  /// Direct chats where the owner asked and hasn't heard back, oldest first.
  final List<OwedToYou> owed;

  const HomeFeed({
    this.needsYou = const [],
    this.promises = const [],
    this.busyGroups = const [],
    this.allGroups = const [],
    this.owed = const [],
  });

  static const empty = HomeFeed();

  static const needsYouShown = 3;
  static const promisesShown = 2;
  static const groupsShown = 3;

  /// A group needs this many messages today to count as busy.
  static const busyAt = 5;

  static const _doneKey = 'home_promises_done_v1';

  /// Today shows at most this many.
  static const owedShown = 3;

  /// Asked this recently, there's been no time to answer.
  static const owedAfter = Duration(hours: 3);

  /// Asked longer ago than this, it's stopped being owed.
  static const owedWithin = Duration(days: 7);

  static Future<HomeFeed> load(DateTime now, {List<RawData>? entries}) async {
    final kept =
        entries ??
        await withoutExcludedSources(await IsarDataSource.getAllEntries());
    final (todos, _) = await TodoStore().load();
    final prefs = await SharedPreferences.getInstance();
    return summarise(
      kept,
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
    final allGroups = <String, List<RawData>>{};
    final chats = <String, RawData>{};
    for (final e in fresh) {
      if (e.thread != null) chats.putIfAbsent(e.thread!, () => e);
      final addressed = Addressed.parse(e.addressed);
      if (addressed == null) continue;
      final title = e.threadTitle;
      if (e.isGroup && title != null && title.isNotEmpty) {
        (allGroups[title] ??= []).add(e);
      }
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
      } else if (classifyWait(
        e.content,
        isGroup: e.isGroup,
        addressed: e.addressed,
      ).needsReply) {
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
              BusyGroup(name: name, count: list.length, messages: list),
        ]..sort((a, b) {
          final byCount = b.count.compareTo(a.count);
          return byCount != 0
              ? byCount
              : b.latest.timestamp.compareTo(a.latest.timestamp);
        });

    final everyGroup =
        [
          for (final MapEntry(key: name, value: list) in allGroups.entries)
            if (list.length >= busyAt)
              BusyGroup(
                name: name,
                count: list.length,
                messages: list,
                needs: _needsOwner(list, turns, now),
              ),
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
      allGroups: everyGroup,
      owed: _owed(entries, turns, now),
    );
  }

  /// A message in the group meant for the owner, that they haven't answered.
  static bool _needsOwner(
    List<RawData> messages,
    MyTurns turns,
    DateTime now,
  ) {
    for (final e in messages) {
      final addressed = Addressed.parse(e.addressed);
      if (addressed != Addressed.mentioned && addressed != Addressed.reply) {
        continue;
      }
      final mine = turns.lastBefore(e.thread, now);
      if (mine != null && mine.at.isAfter(e.timestamp)) continue;
      final reason = classifyWait(
        e.content,
        isGroup: true,
        addressed: e.addressed,
      );
      if (reason.needsReply && reason.kind != WaitKind.unsure) return true;
    }
    return false;
  }

  /// One-to-one chats whose last word is the owner asking something.
  static List<OwedToYou> _owed(
    Iterable<RawData> entries,
    MyTurns turns,
    DateTime now,
  ) {
    final latest = <String, RawData>{};
    for (final e in entries) {
      final thread = e.thread;
      if (thread == null || e.isGroup || Addressed.parse(e.addressed) == null) {
        continue;
      }
      final seen = latest[thread];
      if (seen == null || e.timestamp.isAfter(seen.timestamp)) {
        latest[thread] = e;
      }
    }
    final owed = <OwedToYou>[];
    for (final MapEntry(key: thread, value: chat) in latest.entries) {
      final turn = turns.lastBefore(thread, now);
      if (turn == null || !turn.at.isAfter(chat.timestamp)) continue;
      final waited = now.difference(turn.at);
      if (waited < owedAfter || waited > owedWithin) continue;
      final asked = classifyWait(turn.text, isGroup: false).kind;
      if (asked == WaitKind.unsure || !_asking.contains(asked)) continue;
      owed.add(OwedToYou(chat: chat, turn: turn));
    }
    owed.sort((a, b) => a.turn.at.compareTo(b.turn.at));
    return owed.take(owedShown).toList();
  }

  static const _asking = {
    WaitKind.question,
    WaitKind.request,
    WaitKind.call,
    WaitKind.invite,
    WaitKind.deadline,
  };
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

/// A group that was busy today.
class BusyGroup {
  final String name;
  final int count;

  /// Today's messages in it, newest first.
  final List<RawData> messages;

  /// Someone in it asked the owner something they haven't answered.
  final bool needs;

  const BusyGroup({
    required this.name,
    required this.count,
    required this.messages,
    this.needs = false,
  });

  RawData get latest => messages.first;
}

/// Something the owner asked in a chat that hasn't been answered.
class OwedToYou {
  /// The chat's latest message, for its name and app.
  final RawData chat;
  final MyTurn turn;

  const OwedToYou({required this.chat, required this.turn});

  String get who => chat.sender;
}
