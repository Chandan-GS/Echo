import 'package:flutter/foundation.dart';
import 'package:project_echo/core/services/gemini_service.dart';
import 'package:project_echo/core/services/generation_guard.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Gemini's JSON reply to [prompt], or null when the cloud engine isn't in
/// use or the call fails (the caller then does without). [label] marks it in
/// the debug log, which only ever notes sizes: the prompt and reply carry
/// people's messages, so they never reach the device log.
Future<String?> askGeminiJson(
  String instruction,
  String prompt, {
  String label = 'GEMINI',
}) async {
  final prefs = await SharedPreferences.getInstance();
  final offline = prefs.getBool('is_offline_engine') ?? true;
  final key = prefs.getString('gemini_api_key') ?? '';
  if (offline || key.isEmpty) return null;
  _log('$label prompt: ${prompt.length} chars');
  try {
    final reply = await GeminiService.instance.generateJson(
      key,
      prompt,
      systemInstruction: instruction,
    );
    _log('$label reply (json): ${reply.length} chars');
    if (reply.trim().isNotEmpty) return reply;
  } catch (e) {
    // Gemini that didn't answer in time won't do better streamed; give up
    // rather than keep the caller (the to-do list) waiting minutes more.
    if (e is GeminiFailure && e.cause is GenerationTimeout) {
      _log('$label JSON call timed out');
      return null;
    }
    _log('$label JSON call failed (${e.runtimeType}), retrying streamed');
  }
  // The streaming call is the one briefings and Ask Echo already rely on.
  try {
    final buffer = StringBuffer();
    await for (final chunk in GeminiService.instance.generateStream(
      key,
      '$prompt\n\nReply with the JSON only.',
      systemInstruction: instruction,
    )) {
      buffer.write(chunk.text ?? '');
    }
    final reply = buffer.toString();
    _log('$label reply (stream): ${reply.length} chars');
    return reply.trim().isEmpty ? null : reply;
  } catch (e) {
    _log('$label call failed (${e.runtimeType})');
    return null;
  }
}

void _log(String message) {
  if (kDebugMode) debugPrint(message);
}
