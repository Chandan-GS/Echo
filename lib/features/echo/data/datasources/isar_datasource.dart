import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';

class IsarDataSource {
  static Isar? _isar;

  static Future<Isar> get instance async {
    if (_isar != null) return _isar!;
    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open([RawDataSchema], directory: dir.path);
    return _isar!;
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
}
