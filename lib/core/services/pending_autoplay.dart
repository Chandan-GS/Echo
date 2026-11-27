import 'package:shared_preferences/shared_preferences.dart';

/// The one-shot "play today's briefing as soon as it's open" mark, set when
/// the owner reaches the app from the briefing notification (its body or
/// its Play button) or the home-screen widget.
///
/// The mark carries when it was made, so one left behind (the app was
/// killed before Home read it, or the briefing never came) can't start a
/// briefing hours or days later: it counts for [window] only. An older
/// version stored a plain `pending_autoplay` bool with no time; that one is
/// never trusted, only cleared.
class PendingAutoplay {
  PendingAutoplay._();

  /// Milliseconds since the epoch when the mark was made. Also written by
  /// MainActivity for the widget, as `flutter.pending_autoplay_at` (a Long).
  static const key = 'pending_autoplay_at';

  /// The undated mark older versions left.
  static const legacyKey = 'pending_autoplay';

  /// How long after the tap the briefing may still start on its own: long
  /// enough for a cold start and writing the briefing, short of "later".
  static const window = Duration(minutes: 15);

  /// Marks the briefing to autoplay.
  static Future<void> mark(SharedPreferences prefs, {DateTime? now}) async {
    await prefs.setInt(key, (now ?? DateTime.now()).millisecondsSinceEpoch);
    await prefs.remove(legacyKey);
  }

  /// Whether a mark is waiting and still fresh. Doesn't clear it.
  static bool isPending(SharedPreferences prefs, {DateTime? now}) =>
      isFresh(_at(prefs), now ?? DateTime.now());

  /// Reads and clears the mark: true at most once per mark, and only while
  /// it's fresh.
  static Future<bool> take(SharedPreferences prefs, {DateTime? now}) async {
    final pending = isPending(prefs, now: now);
    await clear(prefs);
    return pending;
  }

  /// Drops the mark, fresh or not.
  static Future<void> clear(SharedPreferences prefs) async {
    await prefs.remove(key);
    await prefs.remove(legacyKey);
  }

  /// Whether a mark made at [at] still counts at [now]. A mark from the
  /// future (the clock was set back) doesn't.
  static bool isFresh(DateTime? at, DateTime now) {
    if (at == null || at.isAfter(now.add(const Duration(minutes: 1)))) {
      return false;
    }
    return now.difference(at) <= window;
  }

  static DateTime? _at(SharedPreferences prefs) {
    final ms = prefs.get(key);
    return ms is int ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }
}
