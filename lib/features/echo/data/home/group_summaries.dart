import 'dart:convert';

import 'package:project_echo/core/services/gemini_json.dart';
import 'package:project_echo/features/echo/data/home/home_feed.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One line per busy group on Home ("Friday is on: 7 PM at Rahul's"),
/// written by Gemini and kept, so a group is summed up again only once it
/// has moved on. Without the cloud engine Home shows the latest message.
class GroupSummaries {
  GroupSummaries._();

  static const _key = 'home_group_summaries_v1';

  /// Summed up again after this many new messages…
  static const _moreMessages = 5;

  /// …or this long after, if anything new came in at all.
  static const _stale = Duration(minutes: 45);

  /// The last line written for each group, by name.
  static Future<Map<String, String>> cached() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      for (final MapEntry(:key, :value) in _decode(
        prefs.getString(_key),
      ).entries)
        if (value['x'] is String) key: value['x'] as String,
    };
  }

  /// Sums up whichever of [groups] have moved on, in one call, and returns
  /// every line known. Unchanged when the call can't be made.
  static Future<Map<String, String>> refresh(
    List<BusyGroup> groups,
    DateTime now,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final store = _decode(prefs.getString(_key));
    final due = [
      for (final g in groups)
        if (needsSummary(store[g.name], g.count, now)) g,
    ];
    if (due.isNotEmpty) {
      final lines = parseReply(
        await askGeminiJson(_instruction, prompt(due), label: 'GROUPS'),
      );
      for (final g in due) {
        final line = lines[g.name];
        if (line == null) continue;
        store[g.name] = {
          'x': line,
          'n': g.count,
          't': now.millisecondsSinceEpoch,
        };
      }
      // Only today's groups are kept.
      store.removeWhere(
        (_, v) => !_sameDay(
          DateTime.fromMillisecondsSinceEpoch((v['t'] as int?) ?? 0),
          now,
        ),
      );
      await prefs.setString(_key, jsonEncode(store));
    }
    return {
      for (final MapEntry(:key, :value) in store.entries)
        if (value['x'] is String) key: value['x'] as String,
    };
  }

  /// Whether a group with [count] messages today needs a new line, given
  /// what was kept for it.
  static bool needsSummary(
    Map<String, dynamic>? kept,
    int count,
    DateTime now,
  ) {
    if (kept == null || kept['x'] is! String) return true;
    final n = (kept['n'] as int?) ?? 0;
    final at = DateTime.fromMillisecondsSinceEpoch((kept['t'] as int?) ?? 0);
    if (!_sameDay(at, now)) return true;
    if (count - n >= _moreMessages) return true;
    return count != n && now.difference(at) >= _stale;
  }

  static const _instruction =
      'You sum up busy group chats for the owner, who wasn’t part of them. '
      'For each group write one plain line, under 70 characters, saying what '
      'it was about or what was decided: plans, times, and anything the owner '
      'might want to know. If it was only chatter, say so in a few words. '
      'No emojis, no quotes. Reply with a JSON object mapping each group’s '
      'name, exactly as given, to its line.';

  /// The groups' messages, oldest first, at most 40 each.
  static String prompt(List<BusyGroup> groups) {
    final b = StringBuffer();
    for (final g in groups) {
      b.writeln('## ${g.name}');
      for (final m in g.messages.take(40).toList().reversed) {
        final text = m.content.replaceAll('\n', ' ');
        b.writeln(
          '${m.sender}: ${text.length > 200 ? '${text.substring(0, 199)}…' : text}',
        );
      }
      b.writeln();
    }
    return b.toString().trim();
  }

  /// {"College gang": "Friday is on…"} from the model's reply, tolerating
  /// a code fence around it.
  static Map<String, String> parseReply(String? reply) {
    if (reply == null) return const {};
    final start = reply.indexOf('{'), end = reply.lastIndexOf('}');
    if (start < 0 || end <= start) return const {};
    try {
      final json = jsonDecode(reply.substring(start, end + 1));
      if (json is! Map) return const {};
      return {
        for (final MapEntry(:key, :value) in json.entries)
          if (value is String && value.trim().isNotEmpty)
            key.toString(): value.trim(),
      };
    } catch (_) {
      return const {};
    }
  }

  static Map<String, Map<String, dynamic>> _decode(String? raw) {
    try {
      final json = jsonDecode(raw ?? '{}') as Map;
      return {
        for (final MapEntry(:key, :value) in json.entries)
          if (value is Map) key as String: Map<String, dynamic>.from(value),
      };
    } catch (_) {
      return {};
    }
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
