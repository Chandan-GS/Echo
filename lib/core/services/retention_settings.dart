import 'package:shared_preferences/shared_preferences.dart';

/// How long Echo keeps what it hears (Settings → History). Every read reloads
/// first: the cleanup also runs in the briefing alarm's own isolate.
class RetentionSettings {
  RetentionSettings._();

  static const daysKey = 'retention_days';
  static const keepSwipedKey = 'retention_keep_swiped';

  /// The choices Settings offers.
  static const options = [1, 3, 7];
  static const defaultDays = 7;

  /// Days to keep a notification. Anything unset or unrecognised is the
  /// default, so an install from before this setting existed only ever keeps
  /// more than it used to.
  static Future<int> days() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return normalise(prefs.getInt(daysKey));
  }

  static Future<void> setDays(int d) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(daysKey, normalise(d));
  }

  /// Whether what the owner swipes away stays in History. On by default.
  static Future<bool> keepSwiped() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getBool(keepSwipedKey) ?? true;
  }

  static Future<void> setKeepSwiped(bool on) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keepSwipedKey, on);
  }

  /// [d] if it's one of [options], otherwise [defaultDays].
  static int normalise(int? d) => options.contains(d) ? d! : defaultDays;
}
