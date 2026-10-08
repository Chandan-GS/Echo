import 'dart:convert';
import 'dart:math' as math;

import 'package:project_echo/features/echo/data/relevance/briefing_selection.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One Ask Echo exchange, kept so follow-ups ("what time was that?", "and
/// Neha?") can be understood.
class ConversationTurn {
  final String question;
  final String answer;
  final List<int> sourceIds;
  final List<double>? embedding;
  final DateTime at;

  const ConversationTurn({
    required this.question,
    required this.answer,
    required this.sourceIds,
    required this.embedding,
    required this.at,
  });

  Map<String, dynamic> toJson() => {
        'q': question,
        'a': answer,
        'ids': sourceIds,
        // 4 decimals is plenty for a similarity check and keeps prefs small.
        'e': embedding?.map((v) => (v * 10000).round() / 10000).toList(),
        't': at.millisecondsSinceEpoch,
      };

  static ConversationTurn fromJson(Map<String, dynamic> j) => ConversationTurn(
        question: j['q'] as String,
        answer: j['a'] as String,
        sourceIds: (j['ids'] as List).cast<int>(),
        embedding: (j['e'] as List?)?.map((v) => (v as num).toDouble()).toList(),
        at: DateTime.fromMillisecondsSinceEpoch(j['t'] as int),
      );
}

/// Today's Ask Echo conversation, persisted across screen visits and wiped
/// when the day changes. Only the last [maxTurns] exchanges are kept, and only
/// the last [historyTurns] are ever shown to the model — and only for
/// questions that look like follow-ups — so memory costs a few dozen tokens
/// at most.
class ConversationMemory {
  static const _prefsKey = 'ask_memory_v1';
  static const maxTurns = 4;
  static const historyTurns = 2;

  /// A follow-up has to come reasonably soon after the question it follows.
  static const followUpWindow = Duration(hours: 3);

  final List<ConversationTurn> turns;
  ConversationMemory._(this.turns);

  ConversationTurn? get last => turns.isEmpty ? null : turns.last;

  static Future<ConversationMemory> load(DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    final turns = <ConversationTurn>[];
    try {
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        for (final j in jsonDecode(raw) as List) {
          turns.add(ConversationTurn.fromJson(j as Map<String, dynamic>));
        }
      }
    } catch (_) {
      // Corrupt or old-format memory: start fresh.
    }
    return ConversationMemory._(
      turns.where((t) => _sameDay(t.at, now)).toList(),
    );
  }

  Future<void> add(ConversationTurn turn) async {
    turns.add(turn);
    while (turns.length > maxTurns) {
      turns.removeAt(0);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(turns.map((t) => t.toJson()).toList()),
    );
  }

  /// Whether [question] continues the previous exchange rather than starting
  /// a new topic. Decided locally — pronouns and connectives, a very short
  /// question, or MiniLM similarity to the previous question.
  bool isFollowUp(String question, List<double>? embedding, DateTime now) {
    final previous = last;
    if (previous == null) return false;
    if (now.difference(previous.at) > followUpWindow) return false;
    if (_followUpPattern.hasMatch(question.trim())) return true;
    if (question.trim().split(RegExp(r'\s+')).length <= 3) return true;
    return cosineSimilarity(embedding, previous.embedding) >= 0.55;
  }

  /// The last few exchanges, compactly, for the prompt.
  String historyForPrompt() => turns
      .skip(math.max(0, turns.length - historyTurns))
      .map((t) => 'User: ${t.question}\nEcho: ${_clip(t.answer, 240)}')
      .join('\n');

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// "and Neha?", "what about tomorrow", "when is it", "did she reply"...
final _followUpPattern = RegExp(
  r'^(and|but|so|also|then|ok(ay)?|what about|how about|what else|anything else)\b'
  r'|\b(he|she|they|him|her|them|his|hers|their|it|its|that one|those|these|same|again|else)\b',
  caseSensitive: false,
);

/// [question] nudged towards [previous] so retrieval for a follow-up like
/// "what time is it?" stays on the earlier topic. Normalized to unit length.
List<double>? blendEmbeddings(
  List<double>? question,
  List<double>? previous, {
  double previousWeight = 0.5,
}) {
  if (question == null || previous == null || question.length != previous.length) {
    return question;
  }
  final blended = [
    for (var i = 0; i < question.length; i++)
      question[i] + previousWeight * previous[i],
  ];
  final norm = math.sqrt(blended.fold<double>(0, (s, v) => s + v * v));
  return norm == 0 ? question : blended.map((v) => v / norm).toList();
}

String _clip(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max).trimRight()}…';
