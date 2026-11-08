import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:project_echo/core/services/engine_gate.dart';
import 'package:project_echo/core/services/retention_settings.dart';
import 'package:project_echo/features/echo/data/context/addressed.dart';
import 'package:project_echo/features/echo/data/context/chat_context_store.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/home/group_summaries.dart';
import 'package:project_echo/features/echo/data/home/home_feed.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/people/data/group_rules.dart';
import 'package:project_echo/features/people/data/people_store.dart';
import 'package:project_echo/features/vault/data/app_access.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Everything on a group's page.
class GroupPage {
  final String title;

  /// The app the group is on, when it's been heard at all.
  final String? source;
  final List<GroupLine> lines;
  final GroupDigest digest;
  final int newSinceYesterday;
  final bool pullsOut;
  final int retentionDays;

  /// Whether the owner has a cloud engine for decisions and asks.
  final bool cloud;

  const GroupPage({
    required this.title,
    required this.source,
    required this.lines,
    required this.digest,
    required this.newSinceYesterday,
    required this.pullsOut,
    required this.retentionDays,
    required this.cloud,
  });

  bool get heardNothing => lines.isEmpty;

  /// A message to reopen the group from.
  RawData? get latest => lines.isEmpty ? null : lines.first.toEntry();
}

/// How many lines "Show everything" lists.
const rawShown = 200;

const _digestOffThreadAt = 400;

class GroupPageStore {
  GroupPageStore._();

  /// Reads the group. Same-named groups on two apps are kept apart: the one
  /// heard from most recently is shown.
  static Future<GroupPage> load(String title, DateTime now) async {
    final isar = await IsarDataSource.instance;
    final retention = await RetentionSettings.days();
    final rows = await isar.rawDatas
        .filter()
        .threadTitleEqualTo(title)
        .and()
        .isGroupEqualTo(true)
        .sortByTimestampDesc()
        .findAll();
    final allowed = await withoutExcludedSources(rows);
    final thread = allowed.isEmpty ? null : allowed.first.thread;
    final mine = [
      for (final e in allowed)
        if (e.thread == thread) GroupLine.of(e),
    ];

    final prefs = await SharedPreferences.getInstance();
    final names = ownerNames(
      prefs.getString('user_name'),
      await ChatContextStore.selfNames(),
    );
    final paid = await PeopleStore.paidKeys();
    final input = (mine, names, now, paid);
    final digest = mine.length < _digestOffThreadAt
        ? _digest(input)
        : await compute(_digest, input);

    final startYesterday = DateTime(now.year, now.month, now.day - 1);
    return GroupPage(
      title: title,
      source: allowed.isEmpty ? null : allowed.first.source,
      lines: mine,
      digest: digest,
      newSinceYesterday: mine
          .where((l) => !l.at.isBefore(startYesterday))
          .length,
      pullsOut: await PeopleStore.groupPullsOut(title),
      retentionDays: retention,
      cloud: await EngineGate.current() == WritingEngine.gemini,
    );
  }

  /// The group summed up, kept from last time if it hasn't moved on.
  /// Only when a cloud engine is on and something came in today.
  static Future<String?> summary(GroupPage page, DateTime now) async {
    if (!page.cloud) return null;
    final today = DateTime(now.year, now.month, now.day);
    final messages = [
      for (final l in page.lines)
        if (!l.at.isBefore(today)) l.toEntry(),
    ];
    if (messages.isEmpty) return null;
    final group = BusyGroup(
      name: page.title,
      count: messages.length,
      messages: messages,
    );
    final lines = await GroupSummaries.refresh([group], now);
    return lines[page.title];
  }
}

GroupDigest _digest((List<GroupLine>, Set<String>, DateTime, Set<String>) i) =>
    digestGroup(i.$1, i.$2, i.$3, paid: i.$4);
