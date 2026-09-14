import 'dart:io';
import 'package:flutter/services.dart';

/// Tells macOS not to throttle this process (App Nap) while a long task like
/// a multi-GB model download is in flight — without this, minimizing the
/// window or losing focus can cut network reads off mid-transfer. No-op on
/// every other platform.
class BackgroundActivityService {
  static const _channel = MethodChannel('project_echo/background_activity');

  static Future<void> begin() async {
    if (!Platform.isMacOS) return;
    try {
      await _channel.invokeMethod('begin');
    } catch (_) {
      // Best-effort — the download still runs, just without the App Nap
      // exemption if the native side is unavailable for any reason.
    }
  }

  static Future<void> end() async {
    if (!Platform.isMacOS) return;
    try {
      await _channel.invokeMethod('end');
    } catch (_) {}
  }
}
