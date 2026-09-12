import 'package:flutter/services.dart';

/// Nudges the native home-screen widget (`EchoBriefingWidgetProvider`) to
/// re-read the cached briefing/streak state and redraw. Best-effort: the
/// widget also refreshes on its own periodic ~30 min tick, so a failure here
/// (e.g. platform channel unavailable) is never fatal — just a slightly
/// staler widget until the next tick.
class WidgetRefreshService {
  static const _channel = MethodChannel('project_echo/widget');

  static Future<void> refresh() async {
    try {
      await _channel.invokeMethod('refresh');
    } catch (_) {
      // Ignore — see class doc.
    }
  }
}
