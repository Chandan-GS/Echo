import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:project_echo/features/echo/data/datasources/tflite_embedding_service.dart';
import 'package:project_echo/features/echo/data/waiting/wait_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The bundled MiniLM's say on messages the rules can't call. It answers
/// after the rules have, in the background, one message at a time; until it
/// has, or if it can't run at all, an unclear message stays on the list.
class WaitModel {
  WaitModel._();

  static const _key = 'wait_intent_verdicts_v1';
  static const _keep = 400;

  /// At most this many messages are read per pass; the rest wait their turn.
  static const _perPass = 12;

  /// Longer than this means the embedding queue is busy with a backlog.
  static const _patience = Duration(seconds: 20);

  /// How much clearer one side has to be than the other.
  static const margin = 0.06;

  static const _needsReply = [
    'Can you send me the file?',
    'Please call me back when you can',
    'What time works for you?',
    'Are you coming tonight?',
    'I need your help with this',
    'Let me know what you think',
    'Did you get my message?',
    'Kal aa raha hai kya?',
    'Mujhe batana kab free ho',
    'Please look at this and reply',
  ];

  static const _noReply = [
    'Thanks a lot',
    'Okay sounds good',
    'Haha that was so funny',
    'Reached home safely',
    'Just letting you know, nothing to do',
    'Good night, take care',
    'The payment went through',
    'Alright, see you later',
    'Theek hai, ho gaya',
    'That movie was great',
  ];

  /// Replaced in tests.
  @visibleForTesting
  static Future<List<double>> Function(String text) embed =
      TfliteEmbeddingService.instance.getEmbedding;

  static List<List<double>>? _needs;
  static List<List<double>>? _none;
  static Future<int>? _running;

  /// What the model has said so far: phrase → whether it needs a reply.
  static Future<Map<String, bool>> cached() async {
    final prefs = await SharedPreferences.getInstance();
    return _decode(prefs.getString(_key));
  }

  /// Reads [texts] that have no verdict yet. Returns how many were decided;
  /// never throws, so an absent model just leaves them unsure.
  static Future<int> resolve(Iterable<String> texts) =>
      _running ??= _resolve(texts.toList()).whenComplete(() => _running = null);

  static Future<int> _resolve(List<String> texts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final kept = _decode(prefs.getString(_key));
      final due = [
        for (final t in texts)
          if (waitPhrase(t).isNotEmpty && !kept.containsKey(_keyOf(t))) t,
      ].take(_perPass).toList();
      if (due.isEmpty) return 0;
      _needs ??= await _embedAll(_needsReply);
      _none ??= await _embedAll(_noReply);
      var decided = 0;
      for (final text in due) {
        final v = await embed(text).timeout(_patience);
        final verdict = resolveGrey(v, _needs!, _none!);
        if (verdict == null) continue;
        kept[_keyOf(text)] = verdict;
        decided++;
      }
      if (decided > 0) {
        while (kept.length > _keep) {
          kept.remove(kept.keys.first);
        }
        await prefs.setString(_key, jsonEncode(kept));
      }
      return decided;
    } catch (e) {
      debugPrint('Waiting: the model couldn\'t help: $e');
      return 0;
    }
  }

  static Future<List<List<double>>> _embedAll(List<String> texts) async => [
    for (final t in texts) await embed(t).timeout(_patience),
  ];

  static String _keyOf(String text) {
    final phrase = waitPhrase(text);
    return phrase.length <= 120 ? phrase : phrase.substring(0, 120);
  }

  /// The key a message's verdict is kept under.
  static String keyFor(String text) => _keyOf(text);

  static Map<String, bool> _decode(String? raw) {
    try {
      final json = jsonDecode(raw ?? '{}');
      if (json is! Map) return {};
      return {
        for (final MapEntry(:key, :value) in json.entries)
          if (value is bool) key as String: value,
      };
    } catch (_) {
      return {};
    }
  }
}

double _dot(List<double> a, List<double> b) {
  var sum = 0.0;
  for (var i = 0; i < a.length && i < b.length; i++) {
    sum += a[i] * b[i];
  }
  return sum;
}

double _closest(List<double> v, List<List<double>> set) {
  var best = -1.0;
  for (final p in set) {
    final d = _dot(v, p);
    if (d > best) best = d;
  }
  return best;
}

/// Whether [v] sits nearer the examples that need a reply (true) or those
/// that don't (false). Null when neither side is clearly closer.
bool? resolveGrey(
  List<double> v,
  List<List<double>> needs,
  List<List<double>> none, {
  double margin = WaitModel.margin,
}) {
  if (v.isEmpty || needs.isEmpty || none.isEmpty) return null;
  final gap = _closest(v, needs) - _closest(v, none);
  if (gap > margin) return true;
  if (gap < -margin) return false;
  return null;
}
