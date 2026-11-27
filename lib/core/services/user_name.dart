import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The owner's name, as given in onboarding or Profile, kept in
/// SharedPreferences under `user_name`. [changed] ticks when it's renamed,
/// so screens kept alive in the background (Home's greeting) catch up.
class UserName {
  UserName._();

  static const key = 'user_name';

  static final changed = ValueNotifier<int>(0);

  /// The name, trimmed; empty when none was given.
  static Future<String> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key)?.trim() ?? '';
  }

  /// Saves [name] (trimmed) and tells listeners.
  static Future<void> save(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, name.trim());
    changed.value++;
  }
}
