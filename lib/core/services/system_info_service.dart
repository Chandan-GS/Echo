import 'dart:io';
import 'package:flutter/services.dart';

/// The proper, user-facing name for this machine — the one macOS shows in
/// System Settings → General → Sharing ("Chandan's MacBook Pro"), not the
/// bare network hostname `Platform.localHostname` returns (which can be a
/// short, personal-looking string with no relation to the actual device).
/// No-op (returns null) on every platform except macOS.
class SystemInfoService {
  static const _channel = MethodChannel('project_echo/system_info');

  static Future<String?> computerName() async {
    if (!Platform.isMacOS) return null;
    try {
      final name = await _channel.invokeMethod<String>('computerName');
      return (name != null && name.trim().isNotEmpty) ? name.trim() : null;
    } catch (_) {
      return null;
    }
  }
}
