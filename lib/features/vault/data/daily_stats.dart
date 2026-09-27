import 'dart:convert';
import 'dart:math' as math;

import 'package:isar/isar.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/relevance/briefing_selection.dart';
import 'package:project_echo/features/vault/data/app_access.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One day's signals as numbers only: the total, per hour, and per Vault
/// category. The notifications themselves aren't kept for this.
class DayStats {
  final DateTime day;
  final List<int> hours; // 24
  final Map<String, int> apps;

  DayStats(this.day, List<int> hours, Map<String, int> apps)
    : hours = List.unmodifiable(hours),
      apps = Map.unmodifiable(apps);

  factory DayStats.empty(DateTime day) =>
      DayStats(day, List.filled(24, 0), const {});

  int get total => hours.fold(0, (a, n) => a + n);

  /// The busiest categories, most first.
  List<MapEntry<String, int>> top(int n) =>
      (apps.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
          .take(n)
          .toList();

  Map<String, dynamic> toJson() => {'h': hours, 'a': apps};

  static DayStats fromJson(DateTime day, Object? json) {
    try {
      final m = json as Map<String, dynamic>;
      final h = List<int>.from(m['h'] as List);
      return DayStats(
        day,
        h.length == 24 ? h : List.filled(24, 0),
        Map<String, int>.from(m['a'] as Map),
      );
    } catch (_) {
      return DayStats.empty(day);
    }
  }

  /// Per hour and per category, the larger of the two — so live counts and
  /// what's still in the Vault can be combined without double counting.
  DayStats mergeMax(DayStats other) => DayStats(
    day,
    [for (var i = 0; i < 24; i++) math.max(hours[i], other.hours[i])],
    {
      for (final k in {...apps.keys, ...other.apps.keys})
        k: math.max(apps[k] ?? 0, other.apps[k] ?? 0),
    },
  );
}

/// Seven days of [DayStats], counted as notifications arrive and kept as
/// numbers in prefs. Anything older than a week is dropped.
class DailyStats {
  DailyStats._();

  static const key = 'vault_daily_stats';
  static const days = 7;

  static String dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Adds one signal to [source]'s count at [at], in a stored map, dropping
  /// days that fell out of the week. Pure, for tests.
  static Map<String, dynamic> added(
    Map<String, dynamic> store,
    String source,
    DateTime at,
    DateTime now,
  ) {
    final k = dateKey(at);
    final day = DayStats.fromJson(_day(at), store[k]);
    final hours = [...day.hours]..[at.hour] += 1;
    final apps = {...day.apps, source: (day.apps[source] ?? 0) + 1};
    return pruned({...store, k: DayStats(day.day, hours, apps).toJson()}, now);
  }

  static Map<String, dynamic> pruned(Map<String, dynamic> store, DateTime now) {
    final keep = {
      for (var i = 0; i < days; i++)
        dateKey(_day(now).subtract(Duration(days: i))),
    };
    return {
      for (final e in store.entries)
        if (keep.contains(e.key)) e.key: e.value,
    };
  }

  /// The last seven days, oldest first, from a stored map.
  static List<DayStats> weekFrom(Map<String, dynamic> store, DateTime now) {
    final today = _day(now);
    return [
      for (var i = days - 1; i >= 0; i--)
        DayStats.fromJson(
          today.subtract(Duration(days: i)),
          store[dateKey(today.subtract(Duration(days: i)))],
        ),
    ];
  }

  /// Called at ingest for every saved notification. Blocked categories and
  /// switched-off apps aren't counted.
  static Future<void> count(String source, DateTime at) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload(); // the background alarm isolate counts too
      final aliases = Map<String, String>.from(
        jsonDecode(prefs.getString('vault_category_aliases') ?? '{}'),
      );
      final shown = displaySource(source, aliases);
      if ((await loadExcludedSources()).contains(shown)) return;
      final store = _decode(prefs.getString(key));
      await prefs.setString(
        key,
        jsonEncode(added(store, shown, at, DateTime.now())),
      );
    } catch (_) {}
  }

  /// The week for the Vault. Today and yesterday are topped up from what's
  /// still in the Vault, which covers the days before counting began.
  static Future<List<DayStats>> week(DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final stored = weekFrom(_decode(prefs.getString(key)), now);

    final aliases = Map<String, String>.from(
      jsonDecode(prefs.getString('vault_category_aliases') ?? '{}'),
    );
    final excluded = await loadExcludedSources();
    final from = _day(now).subtract(const Duration(days: 1));
    final isar = await IsarDataSource.instance;
    final query = isar.rawDatas.filter().timestampGreaterThan(from);
    final sources = await query.sourceProperty().findAll();
    final times = await isar.rawDatas
        .filter()
        .timestampGreaterThan(from)
        .timestampProperty()
        .findAll();

    var live = <String, dynamic>{};
    for (var i = 0; i < math.min(sources.length, times.length); i++) {
      final shown = displaySource(sources[i], aliases);
      if (excluded.contains(shown)) continue;
      live = added(live, shown, times[i], now);
    }
    final fromVault = weekFrom(live, now);
    return [
      for (var i = 0; i < stored.length; i++)
        i >= stored.length - 2 ? stored[i].mergeMax(fromVault[i]) : stored[i],
    ];
  }

  static Map<String, dynamic> _decode(String? raw) {
    try {
      return Map<String, dynamic>.from(jsonDecode(raw ?? '{}') as Map);
    } catch (_) {
      return {};
    }
  }
}
