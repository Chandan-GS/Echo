import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_mascot.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One thing Echo says in his bubble above the nav dock, with the mood his
/// face takes while he says it.
class EchoLine {
  final String text;
  final EchoState mood;

  /// Shown at most once a day under this key (for example "morning").
  final String? onceKey;

  /// Ambient lines (news, heads-ups) respect a quiet gap between them and
  /// never interrupt scrolling. Lines about what Echo is doing right now,
  /// or that answer something the user did, always show.
  final bool ambient;

  final Duration hold;
  final VoidCallback? onTap;

  const EchoLine(
    this.text, {
    this.mood = EchoState.idle,
    this.onceKey,
    this.ambient = true,
    this.hold = const Duration(seconds: 5),
    this.onTap,
  });
}

/// Decides when Echo speaks. It only appears when something changes, keeps
/// a few minutes between ambient lines, and stays out of the way while the
/// user is typing or scrolling.
class EchoSays {
  EchoSays._();
  static final EchoSays instance = EchoSays._();

  static const _gap = Duration(minutes: 3);
  static const _onceKey = 'echo_says_once_v1';

  /// What he's saying now, if anything.
  final ValueNotifier<EchoLine?> current = ValueNotifier(null);

  bool _quiet = false;
  DateTime _scrolledAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _lastAmbient;
  Timer? _timer;

  /// Returns whether the line was shown.
  Future<bool> say(EchoLine line, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    if (_quiet) return false;
    if (line.ambient) {
      if (at.difference(_scrolledAt) < const Duration(milliseconds: 1500)) {
        return false;
      }
      if (_lastAmbient != null && at.difference(_lastAmbient!) < _gap) {
        return false;
      }
    }
    if (line.onceKey != null && !await _firstToday(line.onceKey!, at)) {
      return false;
    }
    if (line.ambient) _lastAmbient = at;
    current.value = line;
    _timer?.cancel();
    _timer = Timer(line.hold, () => hide(line));
    return true;
  }

  /// Hides the bubble, or only [line] if given and still showing.
  void hide([EchoLine? line]) {
    if (line != null && !identical(current.value, line)) return;
    _timer?.cancel();
    current.value = null;
  }

  /// While asking or typing, nothing shows.
  void setQuiet(bool quiet) {
    if (quiet == _quiet) return;
    _quiet = quiet;
    if (quiet) hide();
  }

  /// Scrolling pushes ambient lines out of the way.
  void scrolled() {
    _scrolledAt = DateTime.now();
    if (current.value?.ambient ?? false) hide();
  }

  Future<bool> _firstToday(String key, DateTime at) async {
    final prefs = await SharedPreferences.getInstance();
    final seen = Map<String, String>.from(
      jsonDecode(prefs.getString(_onceKey) ?? '{}') as Map,
    );
    final today = '${at.year}-${at.month}-${at.day}';
    if (seen[key] == today) return false;
    // Keep only today's keys, so the map never grows.
    seen.removeWhere((_, day) => day != today);
    seen[key] = today;
    await prefs.setString(_onceKey, jsonEncode(seen));
    return true;
  }

  @visibleForTesting
  void reset() {
    _timer?.cancel();
    current.value = null;
    _quiet = false;
    _lastAmbient = null;
    _scrolledAt = DateTime.fromMillisecondsSinceEpoch(0);
  }
}
