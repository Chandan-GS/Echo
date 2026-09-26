import 'dart:convert';

import 'package:echo_native/echo_native.dart';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/datasources/tflite_embedding_service.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/relevance/temporal_relevance.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Moves captured notifications and calendar events into Isar. Uses only the
/// echo_native plugin (no Activity-bound channels), so it runs both in the app
/// and in the background briefing alarm.
class NotificationIngest {
  NotificationIngest._();

  /// Saves every notification buffered natively while no UI was listening.
  static Future<void> drainBuffer() async {
    try {
      final buffer = jsonDecode(await EchoNative.drainBuffer());
      if (buffer is! List) return;
      for (final item in buffer) {
        if (item is Map<String, dynamic>) {
          await process(item);
          // Yield to the event loop between items so a large backlog can't
          // starve the UI thread — frames get a chance to paint in between.
          await Future<void>.delayed(Duration.zero);
        }
      }
    } catch (e) {
      debugPrint('Error draining buffer: $e');
    }
  }

  /// Saves calendar events for today and tomorrow — the briefing's horizon —
  /// skipping occurrences already stored.
  static Future<void> syncCalendar() async {
    try {
      final now = DateTime.now();
      final events = jsonDecode(
        await EchoNative.fetchCalendarEvents(
          startOfDay(now),
          briefingHorizonEnd(now),
        ),
      );
      if (events is! List) return;
      final isar = await IsarDataSource.instance;
      for (final item in events) {
        if (item is! Map<String, dynamic>) continue;
        // Title + start time identifies an occurrence, so a daily standup
        // gets one entry per day rather than being deduplicated away.
        final existing = await isar.rawDatas
            .filter()
            .sourceEqualTo('Calendar')
            .senderEqualTo(item['sender'] as String? ?? '')
            .timestampEqualTo(
              DateTime.fromMillisecondsSinceEpoch(item['timestamp'] as int),
            )
            .count();
        if (existing == 0) await process(item);
      }
    } catch (e) {
      debugPrint('Error fetching calendar events: $e');
    }
  }

  /// Embeds one captured notification and writes it to Isar.
  static Future<void> process(Map<String, dynamic> json) async {
    try {
      final rawSource = json['source'] as String? ?? 'Unknown';

      // Load aliases to automatically remap source for RAG & Vault
      final prefs = await SharedPreferences.getInstance();
      final aliasesString = prefs.getString('vault_category_aliases') ?? '{}';
      final Map<String, String> categoryAliases = Map<String, String>.from(
        jsonDecode(aliasesString),
      );

      final defaultSource = rawSource.isEmpty
          ? 'Unknown'
          : '${rawSource[0].toUpperCase()}${rawSource.substring(1).toLowerCase()}';
      final source = categoryAliases[defaultSource] ?? defaultSource;

      final sender = json['sender'] as String? ?? '';
      final content = json['content'] as String? ?? '';
      final timestampMs =
          json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;

      final textToEmbed = '$sender $content'.trim();
      List<double>? embedding;

      if (textToEmbed.isNotEmpty) {
        embedding = await TfliteEmbeddingService.instance.getEmbedding(
          textToEmbed,
        );
      }

      final rawData = RawData()
        ..source = source
        ..sender = sender
        ..content = content
        ..timestamp = DateTime.fromMillisecondsSinceEpoch(timestampMs)
        ..embedding = embedding;

      final isar = await IsarDataSource.instance;
      await isar.writeTxn(() async {
        await isar.rawDatas.put(rawData);
      });

      debugPrint('Saved notification from $source to Isar.');
      // Note: old-notification cleanup runs on launch and on app resume, not
      // per-write — running a full-collection delete after every single save
      // was O(n) per notification and raced with concurrent buffer drains.
    } catch (e) {
      debugPrint('Error processing notification: $e');
    }
  }
}
