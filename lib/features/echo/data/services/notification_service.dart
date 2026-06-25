import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:isar/isar.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/datasources/tflite_embedding_service.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:permission_handler/permission_handler.dart';

class NotificationService with WidgetsBindingObserver {
  static final NotificationService instance = NotificationService._();

  final _methodChannel = const MethodChannel('project_echo/notifications');
  final _eventChannel = const EventChannel('project_echo/notification_stream');

  NotificationService._();

  Future<void> initialize() async {
    try {
      WidgetsBinding.instance.addObserver(this);

      // Cleanup old notifications on launch
      await IsarDataSource.deleteOldNotifications();

      // 0. Fetch today's calendar events silently
      await _fetchAndProcessCalendarEvents();

      // 1. Drain the native buffer (missed notifications while app was closed)
      await _drainBuffer();

      // 2. Listen to live stream for new notifications while app is open
      _eventChannel.receiveBroadcastStream().listen(
        (data) {
          if (data is String) {
            final Map<String, dynamic> item = jsonDecode(data);
            _processNotification(item);
          }
        },
        onError: (e) {
          debugPrint('EventChannel error: $e');
        },
      );
    } catch (e) {
      debugPrint('Error initializing NotificationService: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _drainBuffer();
    }
  }

  Future<void> _drainBuffer() async {
    try {
      final String? bufferJson = await _methodChannel.invokeMethod(
        'drainBuffer',
      );
      if (bufferJson != null && bufferJson.isNotEmpty) {
        final List<dynamic> buffer = jsonDecode(bufferJson);
        for (final item in buffer) {
          if (item is Map<String, dynamic>) {
            await _processNotification(item);
          }
        }
      }
    } catch (e) {
      debugPrint('Error draining buffer: $e');
    }
  }

  Future<void> _fetchAndProcessCalendarEvents() async {
    try {
      final status = await Permission.calendarFullAccess.status;
      // We also check calendar.status for older Android versions
      final legacyStatus = await Permission.calendar.status;
      if (!status.isGranted && !legacyStatus.isGranted) {
        return; // Silently exit if permission not granted
      }

      final String? eventsJson = await _methodChannel.invokeMethod(
        'fetchTodayCalendarEvents',
      );
      if (eventsJson != null && eventsJson.isNotEmpty && eventsJson != '[]') {
        final List<dynamic> events = jsonDecode(eventsJson);
        final isar = await IsarDataSource.instance;

        for (final item in events) {
          if (item is Map<String, dynamic>) {
            final sender = item['sender'] as String? ?? '';

            // Deduplication: Avoid processing the exact same event multiple times today
            final existingCount = await isar.rawDatas
                .filter()
                .sourceEqualTo('Calendar')
                .senderEqualTo(sender)
                .count();

            if (existingCount == 0) {
              await _processNotification(item);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching calendar events: $e');
    }
  }

  Future<void> _processNotification(Map<String, dynamic> json) async {
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
      
      // Auto-cleanup old notifications (older than 24 hours)
      await IsarDataSource.deleteOldNotifications();
    } catch (e) {
      debugPrint('Error processing notification: $e');
    }
  }
}
