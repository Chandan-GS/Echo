import 'dart:async';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_litert_lm/flutter_litert_lm.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_echo/features/echo/data/datasources/briefing_prompt.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';

part 'briefing_state.dart';

class BriefingCubit extends Cubit<BriefingState> {
  LiteLmEngine? _engine;
  LiteLmConversation? _conversation;
  StreamSubscription<LiteLmMessage>? _streamSub;

  BriefingCubit() : super(BriefingInitial()) {
    _loadCachedBriefing();
  }

  Future<void> _loadCachedBriefing() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dateStr = prefs.getString('cached_briefing_date');
      final rawText = prefs.getString('cached_briefing_text');

      final today = DateTime.now().toIso8601String().split('T').first;
      if (dateStr == today && rawText != null && rawText.isNotEmpty) {
        emit(BriefingCached(rawText: rawText, ttsText: stripForTts(rawText)));
      }
    } catch (_) {}
  }

  void playCachedBriefing(String rawText) {
    emit(BriefingReady(rawText: rawText, ttsText: stripForTts(rawText)));
  }

  Future<void> generateBriefing() async {
    emit(BriefingGenerating());

    try {
      final dir = await getApplicationDocumentsDirectory();
      final modelPath = '${dir.path}/deepseek_r1_1_5b.litertlm';

      if (!(await File(modelPath).exists())) {
        emit(
          BriefingError(
            'Model not found. Please complete the onboarding first.',
          ),
        );
        return;
      }

      try {
        _engine = await LiteLmEngine.create(
          LiteLmEngineConfig(modelPath: modelPath, backend: LiteLmBackend.gpu),
        );
      } catch (_) {
        _engine = await LiteLmEngine.create(
          LiteLmEngineConfig(modelPath: modelPath, backend: LiteLmBackend.cpu),
        );
      }

      // ── 2. Build context from Isar mock data ────────────────────────────
      final context = await _buildContext();

      // ── 3. Create conversation — prompt loaded from briefing_prompt.dart ─
      _conversation = await _engine!.createConversation(
        LiteLmConversationConfig(
          systemInstruction: briefingSystemInstruction,
          samplerConfig: const LiteLmSamplerConfig(
            // Lower temperature = more deterministic, less hallucination
            temperature: 0.4,
            topK: 30,
            topP: 0.85,
          ),
        ),
      );

      // ── 4. Stream the response, skipping the <think> block ──────────────
      final StringBuffer buffer = StringBuffer();
      bool inThinkBlock = true; // DeepSeek R1 always starts with <think>

      final Completer<void> done = Completer<void>();

      _streamSub = _conversation!
          .sendMessageStream(buildUserMessage(context))
          .listen(
            (msg) {
              final token = msg.text;

              if (inThinkBlock) {
                // Accumulate until we find </think>
                buffer.write(token);
                final full = buffer.toString();
                final closeIdx = full.indexOf('</think>');
                if (closeIdx != -1) {
                  buffer.clear();
                  final afterThink = full.substring(
                    closeIdx + '</think>'.length,
                  );
                  buffer.write(afterThink.trimLeft());
                  inThinkBlock = false;
                  if (buffer.isNotEmpty) {
                    emit(BriefingGenerating(partial: buffer.toString()));
                  }
                }
                return;
              }

              // Normal decode — append delta and emit live preview
              buffer.write(token);
              emit(BriefingGenerating(partial: buffer.toString()));
            },
            onError: (Object err) {
              emit(BriefingError('Generation failed: $err'));
              if (!done.isCompleted) done.complete();
            },
            onDone: () async {
              var rawText = buffer.toString().trim();
              // Strip residual think tags and model delimiters
              rawText = rawText
                  .replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '')
                  .replaceAll(RegExp(r'<\|[^|]*\|>', dotAll: true), '')
                  .trim();
              // Deterministically strip email sign-off artifacts
              rawText = stripSignOff(rawText);
              // Remove repeated sentences (1.5B models loop)
              rawText = deduplicateSentences(rawText);
              // Strip filler commentary (e.g. "That's a relief", "Important to include")
              rawText = stripFillerCommentary(rawText);
              // Fallback auto-bolding to ensure names, dates, times are wrapped in **
              rawText = autoBold(rawText);

              print(
                '=== ECHO GENERATED OUTPUT ===\n$rawText\n=============================',
              );

              if (rawText.isEmpty) {
                emit(BriefingError('The model produced an empty response.'));
              } else {
                final ttsText = stripForTts(rawText);
                try {
                  final prefs = await SharedPreferences.getInstance();
                  final today = DateTime.now()
                      .toIso8601String()
                      .split('T')
                      .first;
                  await prefs.setString('cached_briefing_date', today);
                  // Cache the raw text (with markdown) for highlight rendering
                  await prefs.setString('cached_briefing_text', rawText);
                } catch (_) {}
                emit(BriefingReady(rawText: rawText, ttsText: ttsText));
              }
              if (!done.isCompleted) done.complete();
            },
          );

      await done.future;
    } catch (e) {
      emit(BriefingError('Error: $e'));
    }
  }

  Future<String> _buildContext() async {
    try {
      final List<RawData> entries = await IsarDataSource.getAllEntries();
      if (entries.isEmpty) {
        return 'No notifications available yet.';
      }
      final lines = entries.map(
        (e) => formatNotification(
          source: e.source,
          sender: e.sender,
          content: e.content,
        ),
      );
      return lines.join('\n');
    } catch (_) {
      return 'No notifications available yet.';
    }
  }

  Future<void> goBack() async {
    _streamSub?.cancel();
    _conversation?.dispose();
    _engine?.dispose();
    _conversation = null;
    _engine = null;

    try {
      final prefs = await SharedPreferences.getInstance();
      final dateStr = prefs.getString('cached_briefing_date');
      final rawText = prefs.getString('cached_briefing_text');

      final today = DateTime.now().toIso8601String().split('T').first;
      if (dateStr == today && rawText != null && rawText.isNotEmpty) {
        emit(BriefingCached(rawText: rawText, ttsText: stripForTts(rawText)));
        return;
      }
    } catch (_) {}

    emit(BriefingInitial());
  }

  void resetBriefing() {
    goBack();
  }

  @override
  Future<void> close() {
    _streamSub?.cancel();
    _conversation?.dispose();
    _engine?.dispose();
    return super.close();
  }
}
