import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:fllama/fllama.dart';
import 'package:project_echo/features/echo/data/datasources/briefing_prompt.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/datasources/tflite_embedding_service.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_echo/core/services/gemini_service.dart';

part 'ask_ai_state.dart';

class AskAiCubit extends Cubit<AskAiState> {
  final List<ChatMessage> _messages = [];
  int? _activeRequestId;

  AskAiCubit() : super(AskAiInitial());

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    cancelInference();

    _messages.add(ChatMessage(sender: 'user', text: text));
    emit(
      AskAiMessageReceived(messages: List.from(_messages), isSearching: true),
    );

    try {
      final dir = await getApplicationDocumentsDirectory();
      final modelPath = '${dir.path}/qwen2.5_1.5b_instruct_q3_k_m.gguf';

      if (!(await File(modelPath).exists())) {
        _messages.add(
          ChatMessage(
            sender: 'echo',
            text:
                'Model not found. Please complete onboarding first to download the model.',
          ),
        );
        emit(
          AskAiMessageReceived(
            messages: List.from(_messages),
            isSearching: false,
          ),
        );
        return;
      }

      print('=== ASK AI: STARTING QUERY SEARCH ===\nQuery: $text');
      // Run on-device RAG using all-MiniLM model
      final queryEmbedding = await TfliteEmbeddingService.instance.getEmbedding(
        text,
      );
      final allNotifications = await IsarDataSource.getAllEntries();
      print('Total notifications in Isar: ${allNotifications.length}');

      // Cosine similarity comparison with Hybrid Keyword Boost
      final queryLower = text.toLowerCase();
      final stopWords = {
        'notification',
        'notifications',
        'message',
        'messages',
        'email',
        'emails',
        'app',
        'from',
        'about',
        'summarize',
        'summarise',
        'what',
        'did',
        'say',
        'the',
        'tell',
        'me',
        'any',
        'update',
        'updates',
        'show',
        'get',
        'give',
      };

      final queryWords = queryLower
          .split(RegExp(r'\W+'))
          .where((w) => w.isNotEmpty && w.length > 2 && !stopWords.contains(w))
          .toSet();

      final scored = allNotifications.map((e) {
        double similarity = _cosineSimilarity(queryEmbedding, e.embedding);

        // Keyword boost for sender or source
        final senderLower = e.sender.toLowerCase();
        final sourceLower = e.source.toLowerCase();
        final metaWords = {
          ...senderLower.split(RegExp(r'\W+')),
          ...sourceLower.split(RegExp(r'\W+')),
        }.where((w) => w.isNotEmpty && !stopWords.contains(w)).toSet();

        bool hasMetaMatch = queryWords.any((qw) => metaWords.contains(qw));
        if (hasMetaMatch) {
          similarity +=
              0.4; // Significant boost for matching the sender or source name precisely
        }

        return _ScoredNotification(e, similarity);
      }).toList();

      scored.sort((a, b) => b.score.compareTo(a.score));

      final Set<String> seenContents = {};
      final List<_ScoredNotification> uniqueScored = [];

      for (final s in scored) {
        if (s.score >= 0.30) {
          final normalizedContent = s.notification.content.toLowerCase().trim();
          if (!seenContents.contains(normalizedContent)) {
            seenContents.add(normalizedContent);
            uniqueScored.add(s);
            if (uniqueScored.length >= 10) break;
          }
        }
      }

      final relevantScored = uniqueScored;
      final List<RawData> ragSources = relevantScored
          .map((s) => s.notification)
          .toList();

      print('=== RAG SIMILARITY SEARCH RESULTS ===');
      for (int i = 0; i < math.min(5, relevantScored.length); i++) {
        final match = relevantScored[i];
        print(
          'Match #${i + 1}: [Score: ${match.score.toStringAsFixed(4)}] Sender: ${match.notification.sender} | Content: ${match.notification.content}',
        );
      }
      print('=====================================');

      String contextString = 'No relevant notifications found in local vault.';
      if (ragSources.isNotEmpty) {
        contextString = ragSources
            .map(
              (e) => formatNotification(
                source: e.source,
                sender: e.sender,
                content: e.content,
              ),
            )
            .join('\n');
      }

      final echoMsgPlaceholder = ChatMessage(
        sender: 'echo',
        text: '',
        isGenerating: true,
        ragSources: ragSources,
      );
      _messages.add(echoMsgPlaceholder);

      emit(
        AskAiMessageReceived(
          messages: List.from(_messages),
          isSearching: false,
        ),
      );

      final prefs = await SharedPreferences.getInstance();
      final isOfflineEngine = prefs.getBool('is_offline_engine') ?? true;
      final geminiApiKey = prefs.getString('gemini_api_key') ?? '';

      final prompt = buildAskAiQwenPrompt(text, contextString);

      print('=== ASK AI: LLM INPUT PROMPT ===');
      _debugPrintLongString(prompt);
      print('================================');

      if (!isOfflineEngine && geminiApiKey.isNotEmpty) {
        final stream = GeminiService.instance.generateStream(
          geminiApiKey,
          prompt,
        );
        String cumulativeBuffer = '';

        await for (final response in stream) {
          if (isClosed) break;
          final chunk = response.text ?? '';
          if (chunk.isNotEmpty) {
            cumulativeBuffer += chunk;
            final lastIdx = _messages.length - 1;
            _messages[lastIdx] = _messages[lastIdx].copyWith(
              text: cumulativeBuffer,
            );
            emit(AskAiMessageReceived(messages: List.from(_messages)));
          }
        }

        final lastIdx = _messages.length - 1;
        _messages[lastIdx] = _messages[lastIdx].copyWith(isGenerating: false);

        var cleanText = _messages[lastIdx].text.trim();
        cleanText = cleanText
            .replaceAll(RegExp(r'<\|im_start\|>.*', dotAll: true), '')
            .replaceAll(RegExp(r'<\|im_end\|>', dotAll: true), '')
            .replaceAll(RegExp(r'<\|[^|]*\|>', dotAll: true), '')
            .trim();
        _messages[lastIdx] = _messages[lastIdx].copyWith(text: cleanText);

        emit(AskAiMessageReceived(messages: List.from(_messages)));
      } else {
        final request = FllamaInferenceRequest(
          contextSize: 1200,
          input: prompt,
          maxTokens: 500,
          modelPath: modelPath,
          numGpuLayers: 99,
          numThreads: 4,
          temperature: 0.3,
          penaltyFrequency: 0.0,
          penaltyRepeat: 1.1,
          topP: 0.9,
        );

        final Completer<void> done = Completer<void>();
        String cumulativeBuffer = '';

        _activeRequestId = await fllamaInference(request, (
          cumulative,
          openaiJson,
          isDone,
        ) {
          if (isClosed) return;

          if (cumulative.length > cumulativeBuffer.length) {
            final delta = cumulative.substring(cumulativeBuffer.length);
            cumulativeBuffer = cumulative;

            final lastIdx = _messages.length - 1;
            _messages[lastIdx] = _messages[lastIdx].copyWith(
              text: _messages[lastIdx].text + delta,
            );
            emit(AskAiMessageReceived(messages: List.from(_messages)));
          }

          if (isDone) {
            final lastIdx = _messages.length - 1;
            _messages[lastIdx] = _messages[lastIdx].copyWith(
              isGenerating: false,
            );

            var cleanText = _messages[lastIdx].text.trim();
            cleanText = cleanText
                .replaceAll(RegExp(r'<\|im_start\|>.*', dotAll: true), '')
                .replaceAll(RegExp(r'<\|im_end\|>', dotAll: true), '')
                .replaceAll(RegExp(r'<\|[^|]*\|>', dotAll: true), '')
                .trim();
            _messages[lastIdx] = _messages[lastIdx].copyWith(text: cleanText);
            print(
              '=== ASK AI: ECHO GENERATED OUTPUT ===\n$cleanText\n=====================================',
            );

            emit(AskAiMessageReceived(messages: List.from(_messages)));
            _activeRequestId = null;
            if (!done.isCompleted) done.complete();
          }
        });

        await done.future;
      }
    } catch (e) {
      if (_messages.isNotEmpty &&
          _messages.last.sender == 'echo' &&
          _messages.last.text.isEmpty) {
        _messages.removeLast();
      }
      _messages.add(
        ChatMessage(
          sender: 'echo',
          text: 'Sorry, I encountered an error running inference: $e',
        ),
      );
      emit(
        AskAiMessageReceived(
          messages: List.from(_messages),
          isSearching: false,
        ),
      );
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

  void cancelInference() {
    if (_activeRequestId != null) {
      fllamaCancelInference(_activeRequestId!);
      _activeRequestId = null;
    }
  }

  @override
  Future<void> close() async {
    cancelInference();
    return super.close();
  }
}

class _ScoredNotification {
  final RawData notification;
  final double score;
  _ScoredNotification(this.notification, this.score);
}
