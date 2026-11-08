import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// When each chat was last opened or read, as recorded by the notification
/// listener (see OpenedChats.kt), so it's right even if the app was killed.
class OpenedChats {
  OpenedChats._();

  /// Written natively as `flutter.echo_opened_chats_v1`.
  static const key = 'echo_opened_chats_v1';

  /// Thread id (the same value as `RawData.thread`) → epoch millis of the
  /// last open or read. Empty on a computer, which has no notifications.
  static Future<Map<String, int>> load() async {
    if (!_hasListener) return const {};
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return decode(prefs.getString(key));
  }

  /// A map read from [raw], or empty if there's nothing usable in it.
  @visibleForTesting
  static Map<String, int> decode(String? raw) {
    if (raw == null) return const {};
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return const {};
      return {
        for (final MapEntry(:key, :value) in json.entries)
          if (value is num) key as String: value.toInt(),
      };
    } catch (_) {
      return const {};
    }
  }

  static bool get _hasListener => !kIsWeb && Platform.isAndroid;
}
