import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/waiting/waiting_store.dart';
import 'package:project_echo/features/people/data/people_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keeps the home-screen widgets current. The widgets read what's stored
/// (briefing, streak, to-dos) and redraw on their own native ticks, so a
/// failure here is never fatal, just a slightly staler widget. While the app
/// runs this also publishes who's waiting ([WaitingStore]) for them to show.
class WidgetRefreshService {
  static const _channel = MethodChannel('project_echo/widget');
  static const _snapshotKey = 'widget_waiting_v1';
  static const _owesKey = 'widget_owes_you_v1';

  /// "Who owes you" reads everyone's history, so it's counted less often.
  static const _owesEvery = Duration(minutes: 5);

  /// Coalesces bursts (a batch of notifications saving one by one).
  static const _debounce = Duration(milliseconds: 1500);

  static Timer? _pending;
  static Future<void>? _publishing;
  static bool _dirty = false;
  static bool _watching = false;
  static DateTime? _owesCountedAt;

  /// Redraws the widgets now and again with a fresh list of who's waiting.
  static Future<void> refresh() async {
    // Once at once with what's stored, once more with the fresh list.
    await _redraw();
    await _publishWaiting();
    await _redraw();
  }

  /// Keeps the widgets in step while the app runs: on every change to the
  /// messages, and each time it comes back to the foreground.
  static Future<void> watch() async {
    if (!Platform.isAndroid || _watching) return;
    _watching = true;
    AppLifecycleListener(onResume: _refreshSoon);
    try {
      final isar = await IsarDataSource.instance;
      isar.rawDatas.watchLazy().listen((_) => _refreshSoon());
    } catch (_) {
      // Resume and direct refreshes still keep it fresh enough.
    }
    _refreshSoon();
  }

  static void _refreshSoon() {
    _pending?.cancel();
    _pending = Timer(_debounce, refresh);
  }

  static Future<void> _redraw() async {
    try {
      await _channel.invokeMethod('refresh');
    } catch (_) {
      // Ignore: see class doc.
    }
  }

  static Future<void> _publishWaiting() async {
    if (!Platform.isAndroid) return;
    final running = _publishing;
    if (running != null) {
      _dirty = true;
      return running;
    }
    final publish = _publish();
    _publishing = publish;
    try {
      await publish;
    } finally {
      _publishing = null;
      if (_dirty) {
        _dirty = false;
        _refreshSoon();
      }
    }
  }

  /// Best-effort: leaves the last list in place if this fails. Runs in the
  /// background too (the briefing alarm's isolate), where the store may take
  /// a moment to open.
  static Future<void> _publish() async {
    try {
      final now = DateTime.now();
      final feed = await WaitingStore.load(now).timeout(
        const Duration(seconds: 5),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _snapshotKey,
        jsonEncode({
          'at': now.millisecondsSinceEpoch,
          'items': [
            for (final item in feed.waiting) _toJson(item.message),
          ],
        }),
      );
    } catch (e) {
      debugPrint('Publishing the widget waiting list failed: $e');
    }
    unawaited(_publishOwes());
  }

  static Future<void> _publishOwes() async {
    final now = DateTime.now();
    final last = _owesCountedAt;
    if (last != null && now.difference(last) < _owesEvery) return;
    _owesCountedAt = now;
    try {
      final people = await PeopleStore.load(now).timeout(
        const Duration(seconds: 10),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _owesKey,
        people.everyone.where((p) => p.loops.owes.isNotEmpty).length,
      );
    } catch (e) {
      debugPrint('Counting who owes you for the widget failed: $e');
    }
  }

  static Map<String, Object?> _toJson(RawData m) => {
    'name': m.sender.isNotEmpty ? m.sender : (m.threadTitle ?? ''),
    'sender': m.sender,
    'source': m.source,
    'thread': m.thread ?? '',
    'since': m.timestamp.millisecondsSinceEpoch,
  };
}
