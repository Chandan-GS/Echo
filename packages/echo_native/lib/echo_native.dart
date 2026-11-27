import 'package:flutter/services.dart';

/// Android-only bridge to Echo's native notification buffer and calendar.
///
/// Unlike the channels in MainActivity, this is a plugin, so it's available in
/// every Flutter engine — including the headless one the briefing alarm runs
/// in.
class EchoNative {
  static const _channel = MethodChannel('echo_native');

  /// Lends out up to [limit] of the oldest notifications captured while no
  /// Flutter UI was listening, as a buffer key → the notification's JSON.
  /// They stay buffered, and are lent again later, until [ackBuffer]ed; a
  /// batch lent to another engine isn't included meanwhile.
  static Future<Map<String, String>> peekBuffer({int limit = 500}) async {
    final reply = await _channel.invokeMapMethod<String, List<Object?>>(
      'peekBuffer',
      {'limit': limit},
    );
    final keys = reply?['keys'] ?? const [];
    final items = reply?['items'] ?? const [];
    return {
      for (var i = 0; i < keys.length && i < items.length; i++)
        keys[i] as String: items[i] as String,
    };
  }

  /// Deletes buffered notifications once they're saved.
  static Future<void> ackBuffer(Iterable<String> keys) =>
      _channel.invokeMethod<void>('ackBuffer', {'keys': keys.toList()});

  /// Calendar event occurrences starting between [start] and [end], as a JSON
  /// array string of `{source, sender, content, timestamp}`. Returns `'[]'`
  /// without calendar permission.
  static Future<String> fetchCalendarEvents(DateTime start, DateTime end) async =>
      await _channel.invokeMethod<String>('fetchCalendarEvents', {
        'startMs': start.millisecondsSinceEpoch,
        'endMs': end.millisecondsSinceEpoch,
      }) ??
      '[]';
}
