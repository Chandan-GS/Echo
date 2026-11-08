import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:project_echo/core/services/writing_engine.dart';
import 'package:project_echo/features/echo/data/ask/ask_intents.dart';
import 'package:project_echo/features/echo/data/context/chat_context_store.dart';
import 'package:project_echo/features/onboarding/data/onboarding_personalization.dart';
import 'package:project_echo/features/settings/data/tone_voice.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Writes one piece of a draft: [writeWith], or a stand-in under test.
typedef DraftWriter =
    Stream<String> Function(
      WritingRoute route,
      WritingPrompt prompt, {
      required int maxTokens,
      required double temperature,
      WritingCancel? cancel,
    });

/// Writes the message Echo offers to send for the owner. It's only ever a
/// draft: nothing goes out until they tap Send.
class ReplyDrafter {
  ReplyDrafter._();

  /// Long enough to wait for the model to load and for an Ask answer ahead
  /// of it to finish; past that, the owner's own words will do.
  static const _patience = Duration(seconds: 60);

  /// One sentence, with room for a long one.
  static const _maxTokens = 80;

  /// Written through whichever engine Ask would use. Falls back to
  /// [localDraft] when there's no engine, or it fails or writes nothing
  /// usable.
  static Future<String> draft(
    ReplyRequest request, {
    Future<WritingRoute> Function(SharedPreferences prefs)? route,
    DraftWriter write = writeWith,
    Duration patience = _patience,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final target = await (route ?? currentWritingRoute)(prefs);
      if (target is NoWritingRoute) return localDraft(request);
      final tone = onboardingToneFromId(prefs.getString('briefing_tone'));
      final prompt = WritingPrompt(
        system: '$draftInstruction ${toneDraftNote(tone)}',
        user: draftPrompt(request, await ChatContextStore.loadMyTurns()),
      );
      Future<String> attempt() async => finishDraft(
        await _collect(
          write(target, prompt, maxTokens: _maxTokens, temperature: 0.3),
          patience,
        ),
      );
      var text = await attempt();
      // The first inference after the model loads can come back blank.
      if (text.isEmpty && target is WriteOnPhone) text = await attempt();
      return text.isEmpty ? localDraft(request) : text;
    } catch (e) {
      debugPrint('Reply draft fell back to the owner\'s own words: $e');
      return localDraft(request);
    }
  }

  /// All of [stream], or an error once [limit] passes. Leaving cancels it,
  /// which frees the on-device model for whatever is next.
  static Future<String> _collect(Stream<String> stream, Duration limit) async {
    final buffer = StringBuffer();
    final done = Completer<String>();
    final sub = stream.listen(
      buffer.write,
      onError: (Object e) {
        if (!done.isCompleted) done.completeError(e);
      },
      onDone: () {
        if (!done.isCompleted) done.complete(buffer.toString());
      },
      cancelOnError: true,
    );
    try {
      return await done.future.timeout(limit);
    } finally {
      await sub.cancel();
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

/// The longest draft Echo offers.
const maxDraftChars = 220;

/// A model's output as a message to send, or empty when it isn't one.
String finishDraft(String raw) {
  final text = clampDraft(cleanDraft(withoutChatTokens(raw)));
  return looksLikeInstructions(text) ? '' : text;
}

/// A small model given little to go on can recite its instructions instead
/// of writing the message.
bool looksLikeInstructions(String text) {
  final lower = text.toLowerCase();
  return lower.contains('the user') ||
      lower.contains('short chat message') ||
      lower.contains('the message being answered');
}

/// The first paragraph, at most [maxDraftChars] long, ending at a sentence
/// or word rather than mid-way.
String clampDraft(String text) {
  final lines = text.split('\n').map((l) => l.trim());
  final first = lines.firstWhere((l) => l.isNotEmpty, orElse: () => '');
  if (first.length <= maxDraftChars) return first;
  var cut = maxDraftChars;
  // Not through the middle of an emoji.
  final unit = first.codeUnitAt(cut - 1);
  if (unit >= 0xD800 && unit <= 0xDBFF) cut--;
  final kept = first.substring(0, cut);
  final sentence = RegExp(r'^.*[.!?।](?=\s)', dotAll: true).stringMatch(kept);
  if (sentence != null && sentence.length >= 40) return sentence;
  final space = kept.lastIndexOf(' ');
  return (space > 0 ? kept.substring(0, space) : kept).trimRight();
}
