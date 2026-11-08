import 'package:isar/isar.dart';
import 'package:project_echo/core/services/retention_settings.dart';
import 'package:project_echo/features/echo/data/context/chat_context_store.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/people/data/people_store.dart';
import 'package:project_echo/features/people/data/person_loops.dart';
import 'package:project_echo/features/people/data/person_tally.dart';
import 'package:project_echo/features/vault/data/app_access.dart';
import 'package:project_echo/features/people/presentation/widgets/people_parts.dart'
    show appLabel;

/// One line in the recent conversation with someone.
/// [turns] with a reply sent through Echo counted once: the app's next
/// notification carries it back as the owner's own line.
List<MyTurn> withoutRepeats(Iterable<MyTurn> turns) {
  final sorted = turns.toList()..sort((a, b) => a.at.compareTo(b.at));
  final kept = <MyTurn>[];
  for (final t in sorted) {
    final repeat = kept.any(
      (k) =>
          k.text.trim() == t.text.trim() &&
          t.at.difference(k.at).abs() < const Duration(minutes: 2),
    );
    if (!repeat) kept.add(t);
  }
  return kept;
}

class TimelineLine {
  final String text;
  final DateTime at;
  final bool mine;
  final String source;

  /// The group it was said in, when it wasn't one-to-one.
  final String? where;

  /// How Echo saw the owner's line: "via Echo", "seen in Whatsapp".
  final String? via;

  const TimelineLine({
    required this.text,
    required this.at,
    required this.mine,
    required this.source,
    this.where,
    this.via,
  });
}

/// A group both the owner and this person are in.
class SharedGroup {
  final String title;
  final String source;
  final int newToday;
  final String? lastLine;

  const SharedGroup({
    required this.title,
    required this.source,
    required this.newToday,
    this.lastLine,
  });
}

/// Everything on a person's page.
class PersonDetail {
  final PersonSummary summary;
  final List<String> members;

  /// "Last message today, 11:01 AM".
  final String lastLine;
  final List<TimelineLine> timeline;
  final List<SharedGroup> groups;
  final PersonChoices choices;

  /// Where a reply would go, or null for someone only ever heard in a group.
  final RawData? replyTo;

  /// The oldest question old enough to follow up, unless nudges are off.
  final OwesLine? followUp;
  final int retentionDays;

  const PersonDetail({
    required this.summary,
    required this.members,
    required this.lastLine,
    required this.timeline,
    required this.groups,
    required this.choices,
    required this.replyTo,
    required this.followUp,
    required this.retentionDays,
  });

  String get first => firstNameOf(summary.name);
}

const _timelineShown = 40;
const _groupsShown = 6;

class PersonDetailStore {
  PersonDetailStore._();

  /// [key] may be any spelling that's since been merged; an unknown key
  /// (a message not tallied yet) still gets a page.
  static Future<PersonDetail> load(String key, DateTime now) async {
    final person = await PeopleStore.person(key);
    final feed = await PeopleStore.load(now);
    final members = person?.members ?? [key];
    final summary = _summaryFor(key, person, feed);
    final isar = await IsarDataSource.instance;
    final choices = await PeopleStore.choicesFor(members);
    final retention = await RetentionSettings.days();

    final sources = person?.sources ?? [key.split('|').first];
    final rows = await isar.rawDatas
        .filter()
        .anyOf(sources, (q, s) => q.sourceEqualTo(s, caseSensitive: false))
        .sortByTimestampDesc()
        .findAll();
    final allowed = await withoutExcludedSources(rows);
    final wanted = members.toSet();
    final theirs = <RawData>[];
    for (final e in allowed) {
      if (!isPersonMessage(e)) continue;
      if (!wanted.contains(personKeyFor(e.sender, e.source))) continue;
      theirs.add(e);
      if (theirs.length >= _timelineShown) break;
    }

    final turns = await ChatContextStore.loadMyTurns();
    final seenMine = await PeopleStore.seenMine();
    final timeline = <TimelineLine>[
      for (final e in theirs)
        TimelineLine(
          text: e.content,
          at: e.timestamp,
          mine: false,
          source: e.source,
          where: e.isGroup ? e.threadTitle : null,
        ),
    ];
    if (person != null) {
      for (final thread in person.directThreads) {
        final source = person.source;
        for (final t in withoutRepeats(
          turns.byThread[thread.key] ?? const <MyTurn>[],
        )) {
          final seen =
              seenMine[thread.key]?.contains(t.at.millisecondsSinceEpoch) ??
              false;
          timeline.add(
            TimelineLine(
              text: t.text,
              at: t.at,
              mine: true,
              source: source,
              via: seen ? 'seen in ${appLabel(source)}' : 'via Echo',
            ),
          );
        }
      }
    }
    timeline.sort((a, b) => a.at.compareTo(b.at));

    final groups = <SharedGroup>[];
    if (person != null) {
      final startToday = DateTime(now.year, now.month, now.day);
      for (final t in person.groupThreads.take(_groupsShown)) {
        final title = t.value.title;
        if (title == null || title.isEmpty) continue;
        final newToday = await isar.rawDatas
            .filter()
            .threadEqualTo(t.key)
            .timestampGreaterThan(startToday)
            .count();
        final last = await isar.rawDatas
            .filter()
            .threadEqualTo(t.key)
            .sortByTimestampDesc()
            .findFirst();
        groups.add(
          SharedGroup(
            title: title,
            source: last?.source ?? person.source,
            newToday: newToday,
            lastLine: last == null
                ? null
                : clip('${firstNameOf(last.sender)}: ${last.content}', 80),
          ),
        );
      }
    }

    final dueFollowUp = choices.dontNudge || !choices.watching
        ? null
        : summary.loops.owes.where((o) => o.followUpDue).firstOrNull;

    RawData? replyTo;
    final direct = person?.directThreads ?? const [];
    if (direct.isNotEmpty) {
      replyTo = RawData()
        ..source = person!.source
        ..sender = person.name
        ..content = ''
        ..timestamp = now
        ..thread = direct.first.key
        ..threadTitle = person.name
        ..isGroup = false
        ..addressed = 'direct';
    }

    return PersonDetail(
      summary: summary,
      members: members,
      lastLine: _lastLine(summary.lastAt, now),
      timeline: timeline.length > _timelineShown
          ? timeline.sublist(timeline.length - _timelineShown)
          : timeline,
      groups: groups,
      choices: choices,
      replyTo: replyTo,
      followUp: dueFollowUp,
      retentionDays: retention,
    );
  }

  static PersonSummary _summaryFor(
    String key,
    MergedPerson? person,
    PeopleFeed feed,
  ) {
    final known = person == null ? key : person.key;
    for (final p in feed.birthdays) {
      if (p.key == known || p.key == key) return p;
    }
    for (final p in feed.everyone) {
      if (p.key == known) return p;
    }
    return PersonSummary(
      key: known,
      name: _nameFromKey(key),
      source: person?.source ?? _appFromKey(key),
      weekCount: 0,
      lastAt: person?.last,
      drifting: false,
      sources: person?.sources ?? [_appFromKey(key)],
      rhythm: '',
    );
  }

  static String _nameFromKey(String key) {
    final name = key.contains('|') ? key.substring(key.indexOf('|') + 1) : key;
    return name
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map(cap)
        .join(' ');
  }

  static String _appFromKey(String key) =>
      key.contains('|') ? cap(key.substring(0, key.indexOf('|'))) : '';

  static String _lastLine(DateTime? at, DateTime now) {
    if (at == null) return '';
    final word = dayWord(at, now);
    final h = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final m = at.minute.toString().padLeft(2, '0');
    final period = at.hour < 12 ? 'AM' : 'PM';
    return 'Last message $word, $h:$m $period';
  }
}

/// How long ago, for "5 weeks" on the Everyone list.
String lastShort(DateTime? at, DateTime now) {
  if (at == null) return '';
  final days = dayOf(now) - dayOf(at);
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return dayWord(at, now);
  final weeks = (days / 7).floor();
  return '$weeks week${weeks == 1 ? '' : 's'}';
}
