import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';

class IsarDataSource {
  static Isar? _isar;

  static Future<Isar> get instance async {
    if (_isar != null && _isar!.isOpen) return _isar!;
    // Reuse an instance already open in THIS isolate rather than re-opening —
    // the static [_isar] field isn't shared across isolates (e.g. the alarm
    // background isolate), so guard against a redundant open on the same env.
    final existing = Isar.getInstance();
    if (existing != null) {
      _isar = existing;
      return existing;
    }
    final dir = await getApplicationDocumentsDirectory();
    // MdbxError (11) / EAGAIN on open is transient lock contention on the MDBX
    // environment (e.g. a background isolate that hasn't released it yet).
    // The error literally means "try again" — retry a few times before failing.
    for (var attempt = 0; ; attempt++) {
      try {
        _isar = await Isar.open([RawDataSchema], directory: dir.path);
        return _isar!;
      } on IsarError {
        if (attempt >= 3) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
  }

  /// Closes the Isar instance for the current isolate and clears the cached
  /// handle. Short-lived background isolates (e.g. the daily-briefing alarm)
  /// MUST call this before they exit — otherwise the abandoned handle leaves
  /// the MDBX lock in a state the next open can't acquire (MdbxError 11).
  static Future<void> close() async {
    await _isar?.close();
    _isar = null;
  }

  static Future<void> seedMockData() async {
    final isar = await instance;

    // Check if already seeded
    final count = await isar.rawDatas.count();
    if (count > 0) {
      return;
    }

    try {
      final jsonString = await rootBundle.loadString('assets/mock_data.json');
      final List<dynamic> jsonList = jsonDecode(jsonString);

      final List<RawData> entries = jsonList.map((json) {
        return RawData()
          ..source = json['source']
          ..sender = json['sender']
          ..content = json['content']
          ..timestamp = DateTime.parse(json['timestamp'])
          ..embedding = (json['embedding'] as List).cast<double>();
      }).toList();

      await isar.writeTxn(() async {
        await isar.rawDatas.putAll(entries);
      });

      debugPrint('Seeded ${entries.length} mock entries into Isar.');
    } catch (e) {
      debugPrint('Error seeding mock data: $e');
    }
  }

  /// Returns all stored notification entries, most recent first.
  static Future<List<RawData>> getAllEntries() async {
    final isar = await instance;
    return isar.rawDatas.where().sortByTimestampDesc().findAll();
  }

  /// Replaces the entire notification set with [entries] in one transaction —
  /// used by the desktop mirror when it receives a fresh snapshot from the
  /// phone (the phone is the source of truth; the desktop just reflects it).
  /// The single writeTxn fires Isar's `watchLazy` once, so the Vault refreshes
  /// automatically. NEVER call this on the phone — it would wipe captured data.
  static Future<void> replaceAllFromSync(List<RawData> entries) async {
    final isar = await instance;
    await isar.writeTxn(() async {
      await isar.rawDatas.clear();
      await isar.rawDatas.putAll(entries);
    });
  }

  /// Deletes all stored notification entries matching the exact source (case-insensitive).
  static Future<void> deleteEntriesBySource(String source) async {
    final isar = await instance;
    await isar.writeTxn(() async {
      final all = await isar.rawDatas.where().findAll();
      final toDelete = all
          .where(
            (e) => e.source.trim().toLowerCase() == source.trim().toLowerCase(),
          )
          .map((e) => e.id)
          .toList();
      await isar.rawDatas.deleteAll(toDelete);
    });
  }

  /// Updates the source name for all entries matching the old source.
  static Future<void> updateEntriesSource(
    String oldSource,
    String newSource,
  ) async {
    final isar = await instance;
    await isar.writeTxn(() async {
      final all = await isar.rawDatas.where().findAll();
      final toUpdate = all
          .where(
            (e) =>
                e.source.trim().toLowerCase() == oldSource.trim().toLowerCase(),
          )
          .toList();

      for (var entry in toUpdate) {
        entry.source = newSource;
      }
      await isar.rawDatas.putAll(toUpdate);
    });
  }

  /// Deletes all notification entries older than 24 hours.
  static Future<void> deleteOldNotifications() async {
    try {
      final isar = await instance;
      final limit = DateTime.now().subtract(const Duration(hours: 24));
      await isar.writeTxn(() async {
        final oldEntries = await isar.rawDatas.filter().timestampLessThan(limit).findAll();
        if (oldEntries.isNotEmpty) {
          final ids = oldEntries.map((e) => e.id).toList();
          await isar.rawDatas.deleteAll(ids);
          debugPrint('Permanently deleted ${ids.length} notifications older than 24 hours.');
        }
      });
    } catch (e) {
      debugPrint('Error cleaning up old notifications: $e');
    }
  }
}
