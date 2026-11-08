import 'package:isar/isar.dart';
import 'package:project_echo/features/echo/data/context/chat_context_store.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/waiting/wait_intent.dart';
import 'package:project_echo/features/people/data/people_store.dart';
import 'package:project_echo/features/vault/data/app_access.dart';

/// Something the owner asked someone for, with no answer since.
class OwedItem {
  final String personKey;
  final String name;
  final String source;

  /// The owner's own words.
  final String what;
  final DateTime askedAt;

  const OwedItem({
    required this.personKey,
    required this.name,
    required this.source,
    required this.what,
    required this.askedAt,
  });

  /// "Asked yesterday", "Asked Tuesday, 3 days", "Asked 9 days ago".
  String askedLabel(DateTime now) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final n = DateTime.utc(now.year, now.month, now.day)
        .difference(DateTime.utc(askedAt.year, askedAt.month, askedAt.day))
        .inDays;
    if (n <= 1) return 'Asked yesterday';
    if (n < 7) return 'Asked ${days[askedAt.weekday - 1]}, $n days';
    return 'Asked $n days ago';
  }
}

/// A thread where the owner spoke last, as [OwedStore] sees it.
class OwedCandidate {
  final MyTurn turn;
  final RawData latest;
  const OwedCandidate(this.turn, this.latest);
}

/// What other people owe the owner. It can only come from what the owner
/// wrote that Echo saw, so a reply typed inside a chat app is invisible and
/// most people will have nothing here. On the phone only.
class OwedStore {
  OwedStore._();

  static const _window = Duration(days: 14);
  static const _settle = Duration(days: 1);
  static const _maxThreads = 40;
  static const maxItems = 8;

  /// Whether [turn] is old enough to be owed, recent enough to matter, and
  /// actually asks for something. Rules only.
  static bool isOpenAsk(MyTurn turn, DateTime now) {
    final age = now.difference(turn.at);
    if (age < _settle || age > _window) return false;
    final kind = classifyWait(turn.text, isGroup: false).kind;
    return kind == WaitKind.question ||
        kind == WaitKind.request ||
        kind == WaitKind.deadline;
  }

  /// Newest first, one per person: asks in one-to-one chats that nothing has
  /// come back on since. Pure, for tests.
  static List<OwedItem> select(List<OwedCandidate> candidates, DateTime now) {
    final out = <String, OwedItem>{};
    final sorted = [...candidates]
      ..sort((a, b) => b.turn.at.compareTo(a.turn.at));
    for (final c in sorted) {
      if (c.latest.isGroup || c.latest.timestamp.isAfter(c.turn.at)) continue;
      if (!isOpenAsk(c.turn, now)) continue;
      final title = c.latest.threadTitle?.trim() ?? '';
      final name = title.isEmpty ? c.latest.sender.trim() : title;
      if (name.isEmpty) continue;
      final key = personKeyFor(name, c.latest.source);
      out.putIfAbsent(
        key,
        () => OwedItem(
          personKey: key,
          name: name,
          source: c.latest.source,
          what: c.turn.text.trim(),
          askedAt: c.turn.at,
        ),
      );
    }
    return out.values.take(maxItems).toList();
  }

  static Future<List<OwedItem>> load(DateTime now) async {
    final turns = await ChatContextStore.loadMyTurns();
    final latestTurn = <String, MyTurn>{
      for (final e in turns.byThread.entries)
        if (e.value.isNotEmpty)
          e.key: e.value.reduce((a, b) => b.at.isAfter(a.at) ? b : a),
    };
    final open =
        latestTurn.entries.where((e) => isOpenAsk(e.value, now)).toList()
          ..sort((a, b) => b.value.at.compareTo(a.value.at));
    if (open.isEmpty) return const [];

    final isar = await IsarDataSource.instance;
    final latest = <RawData, MyTurn>{};
    for (final e in open.take(_maxThreads)) {
      final entry = await isar.rawDatas
          .filter()
          .threadEqualTo(e.key)
          .sortByTimestampDesc()
          .findFirst();
      if (entry != null) latest[entry] = e.value;
    }
    final allowed = await withoutExcludedSources(latest.keys.toList());
    return select([
      for (final entry in allowed) OwedCandidate(latest[entry]!, entry),
    ], now);
  }
}
