import 'package:flutter/services.dart';

/// Android-only bridge to Echo's native notification buffer and calendar.
///
/// Unlike the channels in MainActivity, this is a plugin, so it's available in
/// every Flutter engine — including the headless one the briefing alarm runs
/// in.
class EchoNative {
  static const _channel = MethodChannel('echo_native');

  /// Returns (as a JSON array string) and clears every notification captured
  /// while no Flutter UI was listening.
  static Future<String> drainBuffer() async =>
      await _channel.invokeMethod<String>('drainBuffer') ?? '[]';

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
