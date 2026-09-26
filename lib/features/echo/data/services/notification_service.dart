import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/services/notification_ingest.dart';

class NotificationService with WidgetsBindingObserver {
  static final NotificationService instance = NotificationService._();

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
                NotificationIngest.process(decoded);
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
  /// and tomorrow's calendar, then drain any notifications missed while the
  /// app was closed.
  /// Deliberately not awaited by [initialize] so it can never delay first frame.
  Future<void> _bootstrapBacklog() async {
    try {
      await IsarDataSource.deleteOldNotifications();
      await NotificationIngest.syncCalendar();
      await NotificationIngest.drainBuffer();
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
      NotificationIngest.drainBuffer();
      // Prune stale notifications when returning to the foreground (this no
      // longer runs on every single write — see NotificationIngest.process).
      IsarDataSource.deleteOldNotifications();
    }
  }
}
