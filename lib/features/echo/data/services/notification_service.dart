import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:isar/isar.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/datasources/tflite_embedding_service.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService with WidgetsBindingObserver {
  static final NotificationService instance = NotificationService._();

  final _methodChannel = const MethodChannel('project_echo/notifications');
  final _eventChannel = const EventChannel('project_echo/notification_stream');

  bool _initialized = false;
  StreamSubscription<dynamic>? _streamSubscription;

  NotificationService._();

  Future<void> initialize() async {
    // Guard against double-initialization (e.g. hot restart / re-entry) which
    // would add a second lifecycle observer and a second stream listener,
    // causing every notification to be written twice.
    if (_initialized) return;
    _initialized = true;

    // This whole class bridges Android's NotificationListenerService (see
    // EchoNotificationListenerService.kt) — there's no native handler on
    // macOS/Windows yet, so every call here would just throw
    // MissingPluginException. Desktop-native capture is a separate,
    // not-yet-built feature; skip entirely rather than spam errors.
    if (Platform.isMacOS || Platform.isWindows) return;

    try {
      WidgetsBinding.instance.addObserver(this);

      // Listen to the live stream for new notifications. Cheap to wire up, so
      // it happens synchronously during init.
      _streamSubscription = _eventChannel.receiveBroadcastStream().listen(
        (data) {
          try {
            if (data is String) {
              final decoded = jsonDecode(data);
              if (decoded is Map<String, dynamic>) {
                _processNotification(decoded);
              }
            }
          } catch (e) {
            debugPrint('Error decoding live notification: $e');
          }
        },
        onError: (e) {
          debugPrint('EventChannel error: $e');
        },
      );

      // Heavy backlog work (cleanup, calendar, draining the missed-notification
      // buffer) must NOT block the first frame. Draining can process hundreds
      // of notifications, each running a TFLite embedding + Isar write on the
      // main isolate — awaiting it here (main() awaits initialize() before
      // runApp) froze the app on the splash screen. Run it in the background
      // after startup instead.
      unawaited(_bootstrapBacklog());
    } catch (e) {
      debugPrint('Error initializing NotificationService: $e');
    }
  }

  /// One-time, non-blocking startup work: prune stale entries, pull today's
  /// calendar, then drain any notifications missed while the app was closed.
  /// Deliberately not awaited by [initialize] so it can never delay first frame.
  Future<void> _bootstrapBacklog() async {
    try {
      await IsarDataSource.deleteOldNotifications();
      await _fetchAndProcessCalendarEvents();
      await _drainBuffer();
    } catch (e) {
      debugPrint('Error bootstrapping notification backlog: $e');
    }
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    await _streamSubscription?.cancel();
    _streamSubscription = null;
    _initialized = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _drainBuffer();
      // Prune stale notifications when returning to the foreground (this no
      // longer runs on every single write — see _processNotification).
      IsarDataSource.deleteOldNotifications();
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
            // Yield to the event loop between items so a large backlog can't
            // starve the UI thread — frames get a chance to paint in between.
            await Future<void>.delayed(Duration.zero);
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
      // Note: old-notification cleanup runs on launch and on app resume, not
      // per-write — running a full-collection delete after every single save
      // was O(n) per notification and raced with concurrent buffer drains.
    } catch (e) {
      debugPrint('Error processing notification: $e');
    }
  }
}
