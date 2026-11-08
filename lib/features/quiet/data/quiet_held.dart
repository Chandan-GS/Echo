import 'package:isar/isar.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/vault/data/app_access.dart';

/// One app's share of what quiet hours held, newest first.
class HeldGroup {
  final String source;
  final List<RawData> items;
  const HeldGroup(this.source, this.items);

  int get count => items.length;

  /// A few names behind these messages, for the stack's second line.
  String get who {
    final names = <String>[];
    for (final item in items) {
      final name = item.isGroup && (item.threadTitle?.isNotEmpty ?? false)
          ? item.threadTitle!
          : item.sender;
      if (name.isNotEmpty && !names.contains(name)) names.add(name);
      if (names.length == 4) break;
    }
    return names.join(', ');
  }
}

/// How one run's held messages add up, for the digest's bar.
class HeldSplit {
  final int groups;
  final int deliveries;
  final int other;
  const HeldSplit(this.groups, this.deliveries, this.other);
  int get total => groups + deliveries + other;
}

/// What quiet hours held, read from the "held" marks in History.
class QuietHeld {
  QuietHeld._();

  /// At most this many are read; the rest stay in History.
  static const limit = 2000;

  /// What's been held since [since], up to [until], without excluded apps.
  static Future<List<RawData>> since(DateTime since, {DateTime? until}) async {
    final isar = await IsarDataSource.instance;
    final rows = await isar.rawDatas
        .filter()
        .heldAtGreaterThan(since, include: true)
        .optional<QAfterFilterCondition>(
          until != null,
          (q) => q.heldAtLessThan(until!, include: true),
        )
        .sortByTimestampDesc()
        .limit(limit)
        .findAll();
    return withoutExcludedSources(rows);
  }

  /// [rows] by app, busiest first.
  static List<HeldGroup> group(List<RawData> rows) {
    final bySource = <String, List<RawData>>{};
    for (final row in rows) {
      (bySource[row.source] ??= []).add(row);
    }
    return [
      for (final e in bySource.entries) HeldGroup(e.key, e.value),
    ]..sort((a, b) => b.count.compareTo(a.count));
  }

  static HeldSplit split(List<RawData> rows) {
    var groups = 0, deliveries = 0, other = 0;
    for (final row in rows) {
      if (row.isGroup) {
        groups++;
      } else if (isDelivery(row)) {
        deliveries++;
      } else {
        other++;
      }
    }
    return HeldSplit(groups, deliveries, other);
  }

  /// Keeps to the same apps and phrases as the listener (QuietHours.kt).
  static bool isDelivery(RawData row) =>
      _deliveryApps.hasMatch(row.source) ||
      _deliveryApps.hasMatch(row.sender) ||
      _deliveryWords.hasMatch(row.content);

  static final _deliveryApps = RegExp(
    'swiggy|zomato|blinkit|grofers|zepto|bigbasket|dunzo|amazon|flipkart|'
    'delhivery|bluedart|dtdc|ekart|myntra',
    caseSensitive: false,
  );
  static final _deliveryWords = RegExp(
    r'out for delivery|been delivered|was delivered|has shipped|been shipped|'
    r'dispatched|order (is )?(picked|confirmed|arriving|on the way)',
    caseSensitive: false,
  );
}
