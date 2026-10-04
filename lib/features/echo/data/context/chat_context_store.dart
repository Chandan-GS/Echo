import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// What Echo keeps about conversations beyond the 24-hour life of a
/// notification: when the owner last spoke in each thread, what chat apps
/// call them, and which threads they open or swipe away. All on the device.
///
/// Every write reloads first: the briefing alarm runs in its own isolate with
/// its own copy of the prefs.
class ChatContextStore {
  ChatContextStore._();

  static const _turnsKey = 'echo_my_turns_v1';
  static const _namesKey = 'echo_self_names_v1';
  static const _engagementKey = 'echo_engagement_v1';

  static const _turnsPerThread = 3;
  static const _maxThreads = 400;

  /// Remembers that the owner wrote [text] in [thread] at [at].
  static Future<void> recordMyTurn(
    String thread,
    DateTime at,
    String text,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final all = _decode(prefs.getString(_turnsKey));
    final turns = [
      ...((all[thread] as List?) ?? const []),
      {'t': at.millisecondsSinceEpoch, 'x': _clip(text, 140)},
    ]..sort((a, b) => (a['t'] as int).compareTo(b['t'] as int));
    all[thread] = turns.sublist(
      turns.length > _turnsPerThread ? turns.length - _turnsPerThread : 0,
    );
    _prune(all, (v) => ((v as List).last as Map)['t'] as int);
    await prefs.setString(_turnsKey, jsonEncode(all));
  }

  static Future<MyTurns> loadMyTurns() async {
    final prefs = await SharedPreferences.getInstance();
    return MyTurns.fromJson(_decode(prefs.getString(_turnsKey)));
  }

  /// Keeps a name a chat app gives the owner, for spotting mentions.
  static Future<void> learnSelfName(String name) async {
    final n = name.trim();
    if (n.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final names = prefs.getStringList(_namesKey) ?? const [];
    if (names.contains(n)) return;
    await prefs.setStringList(_namesKey, [...names, n].take(12).toList());
  }

  static Future<List<String>> selfNames() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_namesKey) ?? const [];
  }

  /// Counts a tap ("opened"), a swipe ("dismissed") or a chat read in its
  /// own app ("read", half a tap: it may have been read on another device)
  /// on [thread].
  static Future<void> recordEngagement(
    String thread,
    String action,
    DateTime at,
  ) async {
    final weight = switch (action) {
      'opened' => 1.0,
      'read' => 0.5,
      'dismissed' => -1.0,
      _ => 0.0,
    };
    if (weight == 0) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final all = _decode(prefs.getString(_engagementKey));
    final e = Map<String, dynamic>.from((all[thread] as Map?) ?? const {});
    var o = (e['o'] as num?)?.toDouble() ?? 0;
    var d = (e['d'] as num?)?.toDouble() ?? 0;
    if (weight > 0) {
      o += weight;
    } else {
      d -= weight;
    }
    // Halve old counts now and then, so a habit that changes shows up.
    if (o + d > 40) {
      o /= 2;
      d /= 2;
    }
    all[thread] = {'o': o, 'd': d, 't': at.millisecondsSinceEpoch};
    _prune(all, (v) => (v as Map)['t'] as int);
    await prefs.setString(_engagementKey, jsonEncode(all));
  }

  static Future<Engagement> loadEngagement() async {
    final prefs = await SharedPreferences.getInstance();
    return Engagement.fromJson(_decode(prefs.getString(_engagementKey)));
  }

  static Map<String, dynamic> _decode(String? s) {
    try {
      final v = jsonDecode(s ?? '{}');
      return v is Map<String, dynamic> ? v : {};
    } catch (_) {
      return {};
    }
  }

  static void _prune(Map<String, dynamic> all, int Function(dynamic) time) {
    if (all.length <= _maxThreads) return;
    final oldest = all.keys.toList()
      ..sort((a, b) => time(all[a]).compareTo(time(all[b])));
    for (final k in oldest.take(all.length - _maxThreads)) {
      all.remove(k);
    }
  }

  static String _clip(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max - 1)}…';
}

/// One thing the owner wrote in a thread.
class MyTurn {
  final DateTime at;
  final String text;
  const MyTurn(this.at, this.text);
}

class MyTurns {
  final Map<String, List<MyTurn>> byThread;
  const MyTurns(this.byThread);

  factory MyTurns.fromJson(Map<String, dynamic> json) => MyTurns({
    for (final e in json.entries)
      if (e.value is List)
        e.key: [
          for (final t in e.value as List)
            if (t is Map && t['t'] is int)
              MyTurn(
                DateTime.fromMillisecondsSinceEpoch(t['t'] as int),
                (t['x'] ?? '').toString(),
              ),
        ],
  });

  /// The owner's latest message in [thread] at or before [at].
  MyTurn? lastBefore(String? thread, DateTime at) {
    if (thread == null) return null;
    MyTurn? best;
    for (final t in byThread[thread] ?? const <MyTurn>[]) {
      if (t.at.isAfter(at)) continue;
      if (best == null || t.at.isAfter(best.at)) best = t;
    }
    return best;
  }
}

/// How the owner treats each thread's notifications.
class Engagement {
  /// thread → (opened, dismissed)
  final Map<String, (double, double)> counts;
  const Engagement(this.counts);

  static const none = Engagement({});

  factory Engagement.fromJson(Map<String, dynamic> json) => Engagement({
    for (final e in json.entries)
      if (e.value is Map)
        e.key: (
          ((e.value as Map)['o'] as num?)?.toDouble() ?? 0,
          ((e.value as Map)['d'] as num?)?.toDouble() ?? 0,
        ),
  });

  /// From −1 (always swiped away) to 1 (always opened); 0 when unknown.
  /// Mostly the thread's own record, partly the whole app's, so a new chat
  /// in an app the owner always opens starts out ahead.
  double affinity(String? thread) {
    if (thread == null) return 0;
    final app = _app(thread);
    var ao = 0.0, ad = 0.0;
    for (final e in counts.entries) {
      if (_app(e.key) != app) continue;
      ao += e.value.$1;
      ad += e.value.$2;
    }
    final (to, td) = counts[thread] ?? (0.0, 0.0);
    return 0.7 * _score(to, td) + 0.3 * _score(ao, ad);
  }

  /// Smoothed so one tap doesn't make a thread a favourite.
  static double _score(double opened, double dismissed) =>
      (opened - dismissed) / (opened + dismissed + 3);

  static String _app(String thread) {
    final i = thread.lastIndexOf(':');
    return i < 0 ? thread : thread.substring(0, i);
  }
}
