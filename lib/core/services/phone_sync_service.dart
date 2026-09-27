import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:project_echo/core/services/app_icon_service.dart';
import 'package:project_echo/core/services/desktop_engine_client.dart';
import 'package:project_echo/features/todo/data/todo_store.dart';
import 'package:project_echo/features/vault/data/daily_stats.dart';
import 'package:project_echo/core/services/streak_service.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';

/// Phone side of data sync: pushes a full snapshot of this device's captured
/// notifications, cached briefing and streak to a desktop Echo Engine on the
/// same Wi-Fi, so the computer mirrors the phone. The phone is always the
/// source of truth — this only ever *sends*; it never mutates local data.
///
/// Fires on foreground, after a briefing is cached, and on a slow periodic
/// tick while the app is open. Android can't reliably push while fully killed,
/// so the mirror is "live while the phone app is running", not always-on.
class PhoneSyncService {
  PhoneSyncService._();
  static final PhoneSyncService instance = PhoneSyncService._();

  final Dio _dio = Dio();
  Timer? _timer;
  bool _syncing = false;

  /// Categories whose app icon this session has already sent; icons rarely
  /// change, so each goes across once.
  final Set<String> _sentIcons = {};

  bool get _isDesktop => Platform.isMacOS || Platform.isWindows;

  /// Begins periodic syncing while the app is foregrounded. Idempotent.
  void startPeriodic() {
    if (_isDesktop) return;
    _timer ??= Timer.periodic(const Duration(seconds: 25), (_) => syncNow());
  }

  void stopPeriodic() {
    _timer?.cancel();
    _timer = null;
  }

  /// Pushes one snapshot to the discovered desktop engine. Best-effort and
  /// self-guarded: no-op on desktop, when the user hasn't opted into a
  /// computer, when none is reachable, or when a sync is already in flight.
  Future<void> syncNow() async {
    if (_isDesktop || _syncing) return;
    _syncing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool('prefer_desktop_engine') ?? false)) return;

      final host = await DesktopEngineClient.discoverHost(
        cachedHost: prefs.getString('desktop_engine_host'),
      );
      if (host == null) return;
      await prefs.setString('desktop_engine_host', host);

      final entries = await IsarDataSource.getAllEntries();
      final notifications = entries.map((e) => e.toSyncMap()).toList();

      final date = prefs.getString('cached_briefing_date');
      final text = prefs.getString('cached_briefing_text');
      final briefing = (date != null && text != null)
          ? {'date': date, 'text': text}
          : null;

      final streak = await StreakService().exportSnapshot();

      // What the phone's newer views show, so the computer can show them too:
      // the to-do list, the Vault's week of numbers, when the briefing was
      // made, and each category's real app icon (desktop can't read those).
      await prefs.reload();
      final todos = {
        'items': prefs.getString(TodoStore.itemsKey),
        'meta': prefs.getString(TodoStore.metaKey),
      };
      final icons = <String, String>{};
      for (final source in entries.map((e) => e.source).toSet()) {
        if (_sentIcons.contains(source)) continue;
        final png = await AppIconService.iconFor(source);
        if (png != null) icons[source] = base64Encode(png);
      }

      await _dio.post(
        'http://$host/sync',
        data: jsonEncode({
          'notifications': notifications,
          'briefing': briefing,
          'streak': streak,
          'todos': todos,
          'stats': prefs.getString(DailyStats.key),
          'briefingTime': prefs.getString('cached_briefing_time'),
          'icons': icons,
        }),
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            ...await DesktopEngineClient.authHeaders(),
          },
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      _sentIcons.addAll(icons.keys);
      debugPrint(
        'Phone sync: pushed ${notifications.length} notifications to $host',
      );
    } catch (e) {
      debugPrint('Phone sync failed: $e');
    } finally {
      _syncing = false;
    }
  }
}
