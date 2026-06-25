import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fllama/fllama.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_echo/features/echo/data/datasources/briefing_prompt.dart';
import 'package:project_echo/features/echo/data/datasources/priority_query_embedding.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/datasources/tflite_embedding_service.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/core/services/gemini_service.dart';

part 'briefing_state.dart';

class BriefingCubit extends Cubit<BriefingState> {
  StreamSubscription<String>? _streamSub;

  BriefingCubit() : super(BriefingInitial()) {
    loadCachedBriefing();
  }

  Future<void> loadCachedBriefing() async {
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
      final modelPath = '${dir.path}/qwen2.5_1.5b_instruct_q3_k_m.gguf';

      if (!(await File(modelPath).exists())) {
        emit(
          BriefingError(
            'Model not found. Please complete the onboarding first.',
          ),
        );
        return;
      }

      // ── 2. Get filtered context (Top 15 semantic RAG matches) ──────────────
      final contextObj = await _getFilteredContext();

      if (contextObj['context'] == 'No notifications available yet.') {
        emit(BriefingError('No important notifications available.'));
        return;
      }

      final highestScore = contextObj['highestScore'] as double?;
      print('RAG Highest Similarity Score: $highestScore');

      if (highestScore != null && highestScore < 0.15) {
        final clearSchedule =
            "Echo: No urgent tasks detected for today. Have a clear schedule!";
        emit(BriefingReady(rawText: clearSchedule, ttsText: clearSchedule));
        return;
      }

      // ── 3. REDUCE PHASE: Final briefing generation ────────────────────────
      emit(BriefingGenerating(partial: 'Synthesizing briefing...'));

      final StringBuffer buffer = StringBuffer();
      final Completer<void> done = Completer<void>();
      final controller = StreamController<String>();

      _streamSub = controller.stream.listen(
        (token) {
          buffer.write(token);
        },
        onError: (Object err) {
          emit(BriefingError('Generation failed: $err'));
          if (!done.isCompleted) done.complete();
        },
        onDone: () async {
          var rawText = buffer.toString().trim();
          // Clean up model response formatting
          rawText = rawText
              .replaceAll(RegExp(r'<\|im_start\|>.*', dotAll: true), '')
              .replaceAll(RegExp(r'<\|im_end\|>', dotAll: true), '')
              .replaceAll(RegExp(r'<\|[^|]*\|>', dotAll: true), '')
              .trim();

          rawText = stripSignOff(rawText);
          rawText = deduplicateSentences(rawText);
          rawText = stripFillerCommentary(rawText);
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
              final today = DateTime.now().toIso8601String().split('T').first;
              await prefs.setString('cached_briefing_date', today);
              await prefs.setString('cached_briefing_text', rawText);
            } catch (_) {}
            emit(BriefingReady(rawText: rawText, ttsText: ttsText));
          }
          if (!done.isCompleted) done.complete();
        },
      );

      final prefs = await SharedPreferences.getInstance();
      final isOfflineEngine = prefs.getBool('is_offline_engine') ?? true;
      final geminiApiKey = prefs.getString('gemini_api_key') ?? '';

      final prompt = buildQwenPrompt(contextObj['context'] as String);

      _debugPrintLongString(
        '=== LLM INPUT PROMPT ===\n$prompt\n========================',
      );

      if (!isOfflineEngine && geminiApiKey.isNotEmpty) {
        final stream = GeminiService.instance.generateStream(geminiApiKey, prompt);
        stream.listen((response) {
          final chunk = response.text ?? '';
          if (chunk.isNotEmpty) {
            controller.add(chunk);
          }
        }, onDone: () {
          controller.close();
        }, onError: (e) {
          controller.addError(e);
        });
      } else {
        final request = FllamaInferenceRequest(
          contextSize: 4000,
          input: prompt,
          maxTokens: 4000,
          modelPath: modelPath,
          numGpuLayers: 99,
          numThreads: 4,
          temperature: 0.6,
          penaltyFrequency: 0.0,
          penaltyRepeat: 1.1,
          topP: 0.9,
        );

        try {
          String lastOutput = '';
          fllamaInference(request, (cumulative, openaiJson, isDone) {
            if (cumulative.length > lastOutput.length) {
              final token = cumulative.substring(lastOutput.length);
              lastOutput = cumulative;
              if (token.isNotEmpty) {
                controller.add(token);
              }
            }
            if (isDone == true) {
              controller.close();
            }
          });
        } catch (err) {
          controller.addError(err);
        }
      }

      await done.future;
    } catch (e) {
      emit(BriefingError('Error: $e'));
    }
  }

  double _cosineSimilarity(List<double>? a, List<double>? b) {
    if (a == null || b == null || a.length != b.length) return 0.0;
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 0.0;
    return dotProduct / (math.sqrt(normA) * math.sqrt(normB));
  }

  Future<Map<String, dynamic>> _getFilteredContext() async {
    try {
      final List<RawData> entries = await IsarDataSource.getAllEntries();
      if (entries.isEmpty) {
        return {
          'context': 'No notifications available yet.',
          'highestScore': 0.0,
        };
      }

      // Garbage filter list (Pre-processor)
      final junkSenders = [
        'zomato',
        'swiggy',
        'myntra',
        'lenskart',
        'amazon',
        'uber',
        'hdfc',
        'credit card',
        'makemytrip',
        'apollo',
        'dominos',
        'jio',
        'urban company',
        'blinkit',
        'flipkart',
        'quora',
        'linkedin',
        'medium',
      ];
      final junkKeywords = ['% off', 'otp', 'flash sale', 'discount', 'free'];

      final prefs = await SharedPreferences.getInstance();
      final aliasesString = prefs.getString('vault_category_aliases') ?? '{}';
      final Map<String, String> categoryAliases = Map<String, String>.from(jsonDecode(aliasesString));
      final blockedCategories = prefs.getStringList('vault_blocked_categories') ?? [];

      final candidateEntries = entries.where((e) {
        // Filter out old notifications (older than 24 hours) to keep only current and future events
        if (e.timestamp.isBefore(
          DateTime.now().subtract(const Duration(hours: 24)),
        ))
          return false;

        final senderLower = e.sender.toLowerCase();
        final contentLower = e.content.toLowerCase();
        
        final sourceKey = e.source.trim();
        final defaultSource = sourceKey.isEmpty ? 'Unknown' : 
            '${sourceKey[0].toUpperCase()}${sourceKey.substring(1).toLowerCase()}';
        final displaySource = categoryAliases[defaultSource] ?? defaultSource;

        if (blockedCategories.contains(displaySource)) return false;

        for (final junk in junkSenders) {
          if (senderLower.contains(junk)) return false;
        }
        for (final junk in junkKeywords) {
          if (contentLower.contains(junk)) return false;
        }
        return true;
      }).toList();

      // Deduplicate by exact content to prevent identical mock messages
      // from saturating the top 40 context.
      final uniqueCandidates = <String, RawData>{};
      for (final e in candidateEntries) {
        uniqueCandidates[e.content] = e;
      }

      if (uniqueCandidates.isEmpty) {
        return {
          'context': 'No notifications available yet.',
          'highestScore': 0.0,
        };
      }

      // Semantic Scoring (RAG)
      // Score each candidate against the pre-calculated Priority Query Embedding
      final scoredCandidates = uniqueCandidates.values.map((e) {
        final score = _cosineSimilarity(priorityQueryEmbedding, e.embedding);
        return {'entry': e, 'score': score};
      }).toList();

      // Sort descending by semantic score
      scoredCandidates.sort(
        (a, b) => (b['score'] as double).compareTo(a['score'] as double),
      );

      final highestScore = scoredCandidates.first['score'] as double;

      // STRICT CAP: Take Top 20 semantic matches
      final topEntries = scoredCandidates
          .take(40)
          .map((e) => e['entry'] as RawData)
          .toList();

      final lines = topEntries.map(
        (e) => formatNotification(
          source: e.source,
          sender: e.sender,
          content: e.content,
        ),
      );

      return {'context': lines.join('\n'), 'highestScore': highestScore};
    } catch (_) {
      return {
        'context': 'No notifications available yet.',
        'highestScore': 0.0,
      };
    }
  }

  Future<void> goBack() async {
    _streamSub?.cancel();

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

  void _debugPrintLongString(String text) {
    for (final line in text.split('\n')) {
      if (line.length <= 800) {
        print(line);
      } else {
        int start = 0;
        while (start < line.length) {
          int end = start + 800;
          if (end > line.length) end = line.length;
          print(line.substring(start, end));
          start = end;
        }
      }
    }
  }

  @override
  Future<void> close() async {
    _streamSub?.cancel();
    return super.close();
  }
}
