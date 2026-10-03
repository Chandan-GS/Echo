import 'dart:convert';

import 'package:project_echo/core/services/gemini_json.dart';
import 'package:project_echo/features/desktop/presentation/today/today_logic.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/reply/reply_drafter.dart';
import 'package:project_echo/features/todo/data/todo_planner.dart';

/// Three short replies to offer for a message, to pick from and send.
/// Gemini writes them from the chat when the cloud engine is on; otherwise
/// they're a few plain ones that fit the message. Kept per message while
/// the app is open, so going back to a chat doesn't ask again.
class ReplySuggestions {
  ReplySuggestions._();

  static const count = 3;

  static final _cache = <String, Future<List<String>>>{};

  /// The suggestions for [to], with [chat] (the conversation as shown) for
  /// context. Never empty.
  static Future<List<String>> forEntry(RawData to, List<ChatLine> chat) =>
      _cache.putIfAbsent(sourceKeyOf(to), () async {
        final reply = await askGeminiJson(
          _instruction,
          prompt(to, chat),
          label: 'REPLIES',
        );
        return fill(parse(reply), to);
      });

  static const _instruction =
      'You suggest replies the user could send in a chat, from their own '
      'phone. Write three short options, each under 60 characters, that '
      'answer the last message in different ways (for example yes, no, or '
      'not yet), so the user can pick one. First person, in the same '
      'language and tone as the chat. Never make up names, places, times or '
      'facts that aren\'t in the chat. No quotation marks. Reply with a JSON '
      'array of three strings.';

  static String prompt(RawData to, List<ChatLine> chat) {
    final where = to.isGroup && (to.threadTitle?.isNotEmpty ?? false)
        ? 'the group "${to.threadTitle}"'
        : 'a chat with ${to.sender}';
    final b = StringBuffer('The latest messages in $where, oldest first:\n');
    for (final l in chat.length > 10 ? chat.sublist(chat.length - 10) : chat) {
      b.writeln('${l.mine ? 'User' : l.who}: ${l.text.replaceAll('\n', ' ')}');
    }
    b.write('\nThe message to answer, from ${to.sender}: "${to.content}"');
    return b.toString();
  }

  /// The replies in a model's answer: a JSON array, or an object holding
  /// one, tolerating a code fence around it.
  static List<String> parse(String? reply) {
    if (reply == null) return const [];
    final start = reply.indexOf(RegExp(r'[\[{]'));
    final end = reply.lastIndexOf(RegExp(r'[\]}]'));
    if (start < 0 || end <= start) return const [];
    try {
      var json = jsonDecode(reply.substring(start, end + 1));
      if (json is Map) json = json.values.whereType<List>().firstOrNull;
      if (json is! List) return const [];
      final seen = <String>{};
      return [
        for (final s in json.whereType<String>())
          if (cleanDraft(s) case final t when t.isNotEmpty && seen.add(t)) t,
      ].take(count).toList();
    } catch (_) {
      return const [];
    }
  }

  /// [got] topped up to [count] with [local] ones.
  static List<String> fill(List<String> got, RawData to) => [
    ...got,
    ...local(to).where((s) => !got.contains(s)),
  ].take(count).toList();

  /// Plain replies that fit most messages of [to]'s kind.
  static List<String> local(RawData to) {
    final text = to.content.toLowerCase();
    if (RegExp(r'\bcall\b').hasMatch(text)) {
      return const [
        'Will call you soon',
        'Can I call you in a bit?',
        'Busy right now, I’ll call later',
      ];
    }
    if (RegExp(r'\b(thanks|thank you|thx|ty)\b').hasMatch(text)) {
      return const ['You’re welcome!', 'Anytime 🙂', 'Happy to help'];
    }
    if (text.contains('?') ||
        RegExp(
          r'\b(confirm|let me know|can you|could you|are you|will you|'
          r'need to know)\b',
        ).hasMatch(text)) {
      return const [
        'Yes, that works',
        'Sorry, I can’t',
        'Let me check and get back to you',
      ];
    }
    return const ['Got it, thanks', 'On it', 'Will get back to you soon'];
  }
}
