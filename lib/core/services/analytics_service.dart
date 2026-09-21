import 'package:aptabase_flutter/aptabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thin, privacy-respecting wrapper over Aptabase.
///
/// Every call is gated on a user opt-out flag, and events carry ONLY an event
/// name plus small, non-PII properties — "what happened", never "what it said".
/// Do not pass notification, message, or briefing content through here.
class Analytics {
  static const _prefKey = 'analytics_enabled';

  /// Defaults to on; flipped to the persisted value by [load] at startup.
  static bool _enabled = true;

  /// Load the user's opt-out preference. Call once during app startup.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_prefKey) ?? true;
  }

  static bool get isEnabled => _enabled;

  /// Toggle analytics on/off — wire this to a Settings switch.
  static Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
  }

  /// Record an anonymous usage event. No-op when the user has opted out.
  static void track(String event, [Map<String, dynamic>? props]) {
    if (!_enabled) return;
    Aptabase.instance.trackEvent(event, props);
  }
}
