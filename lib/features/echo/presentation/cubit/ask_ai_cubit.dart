import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fllama/fllama.dart';
import 'package:project_echo/features/echo/data/datasources/briefing_prompt.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/datasources/tflite_embedding_service.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_echo/core/services/gemini_service.dart';
import 'package:project_echo/core/services/desktop_engine_client.dart';
import 'package:project_echo/core/services/offline_model_repository.dart';

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

    // Index of the echo placeholder for THIS request. Captured once so that
    // streaming callbacks always write to their own message even if the list
    // grows from a later request (appends never shift earlier indices).
    int? echoIndex;

    try {
      final modelPath = await createOfflineModelRepository().downloadedPathOrNull();

      if (modelPath == null) {
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
      // Run on-device RAG using all-MiniLM model. The TensorFlow Lite native
      // library isn't bundled on desktop (macOS/Windows), and notifications
      // synced from the phone carry no embeddings anyway, so on desktop we skip
      // embeddings entirely and fall back to keyword-only retrieval (the +0.4
      // sender/source keyword boost below still surfaces relevant items).
      List<double>? queryEmbedding;
      if (!(Platform.isMacOS || Platform.isWindows)) {
        try {
          queryEmbedding =
              await TfliteEmbeddingService.instance.getEmbedding(text);
        } catch (e) {
          print('Embedding unavailable — keyword-only retrieval: $e');
        }
      }
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

        // Keyword boost for the notification's own text — metadata alone
        // misses a plain-language query whose words simply appear in what
        // the notification actually says. This matters most on desktop,
        // which has no embeddings to fall back on (see the queryEmbedding
        // guard above), so this is the only way content itself counts there.
        final contentLower = e.content.toLowerCase();
        final contentWords = contentLower
            .split(RegExp(r'\W+'))
            .where((w) => w.isNotEmpty && !stopWords.contains(w))
            .toSet();
        if (queryWords.any((qw) => contentWords.contains(qw))) {
          similarity += 0.35;
        }

        // A query clearly asking about the weather should still find a
        // weather notification even when neither the query nor the
        // notification's sender ever uses the word "weather" itself — e.g. a
        // system weather alert's sender is just "Google" and its content
        // reads "29° in Bengaluru · Mostly cloudy", with zero literal
        // keyword overlap against "what's the weather like today".
        if (_isWeatherQuery(queryWords) && _looksLikeWeather(contentLower)) {
          similarity += 0.5;
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

      // No real match on an actual lookup question: don't hand a small local
      // model an empty context and hope it improvises sensibly — on thin
      // context, the 1.5B model reliably degenerates into paraphrasing its own
      // system instruction back at the user instead of answering. Answer
      // directly instead of invoking generation at all — the same defensive
      // short-circuit the briefing cubit uses for a low RAG confidence score.
      // Casual small talk ("hi", "thanks") never needed notification context
      // in the first place, so it still goes to the model normally — the
      // model generating a warm, natural reply here isn't the failure mode we
      // were guarding against.
      if (ragSources.isEmpty && !_isSmallTalk(text)) {
        final name = (await SharedPreferences.getInstance())
                .getString('user_name') ??
            'sir';
        _messages.add(
          ChatMessage(
            sender: 'echo',
            text: _noMatchFallback(name, allNotifications),
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

      final contextString = ragSources.isEmpty
          ? 'No notifications needed — this is just a casual message.'
          : ragSources
              .map(
                (e) => formatNotification(
                  source: e.source,
                  sender: e.sender,
                  content: e.content,
                ),
              )
              .join('\n');

      final echoMsgPlaceholder = ChatMessage(
        sender: 'echo',
        text: '',
        isGenerating: true,
        ragSources: ragSources,
      );
      _messages.add(echoMsgPlaceholder);
      echoIndex = _messages.length - 1;

      emit(
        AskAiMessageReceived(
          messages: List.from(_messages),
          isSearching: false,
        ),
      );

      final prefs = await SharedPreferences.getInstance();
      final isOfflineEngine = prefs.getBool('is_offline_engine') ?? true;
      final geminiApiKey = prefs.getString('gemini_api_key') ?? '';
      final userName = prefs.getString('user_name') ?? 'Sir';

      // Phone-first, computer-optional — same bounded reachability check as
      // the briefing cubit; falls straight through to on-device/Gemini if no
      // desktop engine answers in time. Desktop builds never offload to
      // ANOTHER desktop engine — this computer already generates locally, so
      // "prefer a computer" only means anything on a phone. Without this
      // guard, a desktop build that ever had prefer_desktop_engine=true
      // (e.g. leftover from earlier testing) could discover and call itself
      // over HTTP, which now correctly gets rejected once pairing has ever
      // happened — better to just never attempt it on desktop.
      final preferDesktopEngine = !(Platform.isMacOS || Platform.isWindows) &&
          (prefs.getBool('prefer_desktop_engine') ?? false);
      String? desktopHost;
      if (preferDesktopEngine) {
        desktopHost = await DesktopEngineClient.discoverHost(
          cachedHost: prefs.getString('desktop_engine_host'),
        );
        if (desktopHost != null) {
          await prefs.setString('desktop_engine_host', desktopHost);
        }
      }
      final useDesktopEngine = desktopHost != null;

      final prompt = buildAskAiQwenPrompt(text, contextString, userName);

      print('=== ASK AI: LLM INPUT PROMPT ===');
      _debugPrintLongString(prompt);
      print('================================');

      if (useDesktopEngine) {
        final stream = DesktopEngineClient.generateStream(
          host: desktopHost,
          endpoint: 'ask',
          prompt: prompt,
        );
        String cumulativeBuffer = '';

        await for (final chunk in stream) {
          if (isClosed) break;
          if (chunk.isNotEmpty) {
            cumulativeBuffer += chunk;
            final lastIdx = echoIndex;
            _messages[lastIdx] = _messages[lastIdx].copyWith(
              text: cumulativeBuffer,
            );
            emit(AskAiMessageReceived(messages: List.from(_messages)));
          }
        }

        final lastIdx = echoIndex;
        _messages[lastIdx] = _messages[lastIdx].copyWith(isGenerating: false);
        emit(AskAiMessageReceived(messages: List.from(_messages)));
      } else if (!isOfflineEngine && geminiApiKey.isNotEmpty) {
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
            final lastIdx = echoIndex;
            _messages[lastIdx] = _messages[lastIdx].copyWith(
              text: cumulativeBuffer,
            );
            emit(AskAiMessageReceived(messages: List.from(_messages)));
          }
        }

        final lastIdx = echoIndex;
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
          // fllama splits the context across parallel slots, so the usable
          // window is only contextSize / n_parallel. 16384 keeps the usable
          // slot at ~2048+ tokens, and keeping it identical to the briefing
          // request lets the loaded model be reused instead of reloaded when
          // switching between the two.
          contextSize: 16384,
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

            final lastIdx = echoIndex!;
            _messages[lastIdx] = _messages[lastIdx].copyWith(
              text: _messages[lastIdx].text + delta,
            );
            emit(AskAiMessageReceived(messages: List.from(_messages)));
          }

          if (isDone) {
            final lastIdx = echoIndex!;
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
      // Remove this request's own placeholder if it never received any text,
      // identified by its captured index rather than "the last message".
      if (echoIndex != null &&
          echoIndex >= 0 &&
          echoIndex < _messages.length &&
          _messages[echoIndex].sender == 'echo' &&
          _messages[echoIndex].text.isEmpty) {
        _messages.removeAt(echoIndex);
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

  // Casual openers/closers that never need notification context to answer —
  // matched as the whole (trimmed) message so a real question that happens to
  // contain one of these words ("thanks for the update on my WhatsApp?")
  // still falls through to normal RAG handling.
  static final RegExp _smallTalkPattern = RegExp(
    r"^(hi+|hey+|hello+|yo|sup|what'?s up|"
    r"good\s*(morning|afternoon|evening|night)|"
    r"how('?s| is| are) it going|how are you( doing)?|"
    r"thanks?( you)?|thx|ty|"
    r"ok(ay)?|cool|nice|great|got it|sounds good|"
    r"bye|goodbye|see (you|ya)|good ?night)[\s!.?]*$",
    caseSensitive: false,
  );

  bool _isSmallTalk(String text) => _smallTalkPattern.hasMatch(text.trim());

  static const _weatherQueryWords = {
    'weather', 'forecast', 'temperature', 'rain', 'raining', 'rainy',
    'sunny', 'cloudy', 'climate', 'hot', 'cold', 'humid', 'humidity',
    'storm', 'wind', 'windy', 'snow', 'snowing',
  };

  bool _isWeatherQuery(Set<String> queryWords) =>
      queryWords.any(_weatherQueryWords.contains);

  static final RegExp _degreePattern = RegExp(r'\d+\s*°');
  static const _weatherContentMarkers = [
    'cloudy', 'forecast', 'rain', 'sunny', 'humidity', 'storm',
    'clear sky', 'overcast',
  ];

  bool _looksLikeWeather(String contentLower) {
    if (_degreePattern.hasMatch(contentLower)) return true;
    return _weatherContentMarkers.any(contentLower.contains);
  }

  /// A dead-end "I don't know" helps no one — point $name at what's actually
  /// in the vault instead, so a miss still leaves them with something useful
  /// to ask next.
  String _noMatchFallback(String name, List<RawData> allNotifications) {
    if (allNotifications.isEmpty) {
      return "I haven't captured any notifications yet, $name — once some "
          "come in, ask me anything about them.";
    }

    final counts = <String, int>{};
    for (final n in allNotifications) {
      final source = n.source.trim();
      final label = source.isEmpty
          ? 'Unknown'
          : '${source[0].toUpperCase()}${source.substring(1).toLowerCase()}';
      counts[label] = (counts[label] ?? 0) + 1;
    }
    final topSources = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final mentioned = topSources
        .take(2)
        .map((e) => '${e.value} from ${e.key}')
        .join(' and ');

    return "I don't see anything about that in your notifications, $name — "
        "but I do have $mentioned if that's useful instead.";
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
