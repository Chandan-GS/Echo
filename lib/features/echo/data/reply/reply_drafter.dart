import 'package:flutter/foundation.dart';
import 'package:project_echo/core/services/gemini_service.dart';
import 'package:project_echo/features/echo/data/ask/ask_intents.dart';
import 'package:project_echo/features/echo/data/context/chat_context_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Writes the message Echo offers to send for the owner. It's only ever a
/// draft: nothing goes out until they tap Send.
class ReplyDrafter {
  ReplyDrafter._();

  static Future<String> draft(ReplyRequest request) async {
    final prefs = await SharedPreferences.getInstance();
    final offline = prefs.getBool('is_offline_engine') ?? true;
    final key = prefs.getString('gemini_api_key') ?? '';
    if (offline || key.isEmpty) return localDraft(request);
    try {
      final turns = await ChatContextStore.loadMyTurns();
      final buffer = StringBuffer();
      await for (final chunk in GeminiService.instance.generateStream(
        key,
        draftPrompt(request, turns),
        systemInstruction: draftInstruction,
      )) {
        buffer.write(chunk.text ?? '');
      }
      final text = cleanDraft(buffer.toString());
      return text.isEmpty ? localDraft(request) : text;
    } catch (e) {
      debugPrint('Reply draft fell back to the owner\'s own words: $e');
      return localDraft(request);
    }
  }
}

const draftInstruction =
    'You write a short chat message that the user will send from their own '
    'phone, as a reply in an existing conversation. Write only the message '
    'itself: first person, in the same language and tone as the conversation, '
    'usually one sentence, no quotation marks, no greeting or sign-off unless '
    'it fits naturally. Never add facts, promises or plans the user didn\'t '
    'give.';

String draftPrompt(ReplyRequest request, MyTurns turns) {
  final e = request.to;
  final where = e.isGroup && (e.threadTitle?.isNotEmpty ?? false)
      ? '${e.sender} in the group "${e.threadTitle}"'
      : e.sender;
  final said = turns.lastBefore(e.thread, e.timestamp);
  final gist = request.gist;
  return [
    if (said != null) 'Earlier, the user wrote: "${said.text}"',
    'The message being answered, from $where: "${e.content}"',
    gist == null
        ? 'The user hasn\'t said what to reply. Suggest a short, natural reply '
              'that commits to nothing: no times, places, plans or facts. An '
              'acknowledgement or a question back is fine.'
        : 'What the user wants to say: $gist',
  ].join('\n');
}

/// Without a model, the owner's own words, tidied: "i'll bring it" →
/// "I'll bring it". With nothing said, an empty draft to type into.
String localDraft(ReplyRequest request) {
  final gist = request.gist?.trim() ?? '';
  if (gist.isEmpty) return '';
  final fixed = gist.replaceAllMapped(
    RegExp(r"(^|\s)i(?=('|\s|$))"),
    (m) => '${m[1]}I',
  );
  return '${fixed[0].toUpperCase()}${fixed.substring(1)}';
}

/// A model's draft without wrapping quotes or a "Reply:" label.
String cleanDraft(String raw) {
  var text = raw.trim();
  text = text.replaceFirst(
    RegExp(r'^(reply|message)\s*:\s*', caseSensitive: false),
    '',
  );
  if (text.length >= 2 &&
      '"“\''.contains(text[0]) &&
      '"”\''.contains(text[text.length - 1])) {
    text = text.substring(1, text.length - 1).trim();
  }
  return text;
}
