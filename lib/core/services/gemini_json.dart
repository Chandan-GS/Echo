import 'package:flutter/foundation.dart';
import 'package:project_echo/core/services/gemini_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Gemini's JSON reply to [prompt], or null when the cloud engine isn't in
/// use or the call fails (the caller then does without). [label] marks it in
/// the debug log.
Future<String?> askGeminiJson(
  String instruction,
  String prompt, {
  String label = 'GEMINI',
}) async {
  final prefs = await SharedPreferences.getInstance();
  final offline = prefs.getBool('is_offline_engine') ?? true;
  final key = prefs.getString('gemini_api_key') ?? '';
  if (offline || key.isEmpty) return null;
  debugPrint('=== $label PROMPT ===\n$prompt\n==================');
  try {
    final reply = await GeminiService.instance.generateJson(
      key,
      prompt,
      systemInstruction: instruction,
    );
    debugPrint('=== $label REPLY (json) ===\n$reply\n==================');
    if (reply.trim().isNotEmpty) return reply;
  } catch (e) {
    debugPrint('$label JSON call failed, retrying with the streaming call: $e');
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
    debugPrint('=== $label REPLY (stream) ===\n$reply\n==================');
    return reply.trim().isEmpty ? null : reply;
  } catch (e) {
    debugPrint('$label call failed: $e');
    return null;
  }
}
