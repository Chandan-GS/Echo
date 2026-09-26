import 'dart:async';
import 'dart:io';
import 'package:project_echo/core/services/analytics_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fllama/fllama.dart';
import 'package:project_echo/features/echo/data/ask/ask_retrieval.dart';
import 'package:project_echo/features/echo/data/ask/conversation_memory.dart';
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

    Analytics.track('ask_echo_used');

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
      // The on-device model is only needed for the offline (Fllama) path below.
      // Cloud (Gemini) and desktop-engine paths don't require it, so we no
      // longer hard-gate here — the offline branch guards on modelPath itself.
      final modelPath = await createOfflineModelRepository().downloadedPathOrNull();

      final now = DateTime.now();
      final smallTalk = isSmallTalk(text);

      print('=== ASK AI: STARTING QUERY SEARCH ===\nQuery: $text');
      // Run on-device RAG using all-MiniLM model. The TensorFlow Lite native
      // library isn't bundled on desktop (macOS/Windows), and notifications
      // synced from the phone carry no embeddings anyway, so on desktop we skip
      // embeddings entirely and fall back to keyword + time retrieval.
      List<double>? queryEmbedding;
      if (!smallTalk && !(Platform.isMacOS || Platform.isWindows)) {
        try {
          queryEmbedding =
              await TfliteEmbeddingService.instance.getEmbedding(text);
        } catch (e) {
          print('Embedding unavailable — keyword-only retrieval: $e');
        }
      }

      // Today's conversation. A follow-up ("and Neha?", "when is it?") is
      // spotted locally, then retrieval leans towards the previous topic and
      // the prompt gets the last couple of exchanges — nothing otherwise.
      final memory = await ConversationMemory.load(now);
      final previous = memory.last;
      final followUp =
          !smallTalk && memory.isFollowUp(text, queryEmbedding, now);

      final allNotifications = await IsarDataSource.getAllEntries();
      print('Total notifications in Isar: ${allNotifications.length}');

      final ranked = smallTalk
          ? const <RankedNotification>[]
          : rankForQuestion(
              question: text,
              now: now,
              entries: allNotifications,
              questionEmbedding: followUp
                  ? blendEmbeddings(queryEmbedding, previous!.embedding)
                  : queryEmbedding,
              carriedIds:
                  followUp ? previous!.sourceIds.toSet() : const <int>{},
            );
      var ragSources = ranked.map((r) => r.entry).toList();

      // A follow-up that matches nothing new ("what time was that?") is still
      // about the previous answer's notifications.
      if (ragSources.isEmpty && followUp) {
        final ids = previous!.sourceIds.toSet();
        ragSources =
            allNotifications.where((e) => ids.contains(e.id)).toList();
      }

      print('=== RAG RESULTS (follow-up: $followUp) ===');
      for (final match in ranked.take(5)) {
        print(
          '[Score: ${match.score.toStringAsFixed(4)}] Sender: ${match.entry.sender} | Content: ${match.entry.content}',
        );
      }
      print('=====================================');

      // No real match on an actual lookup question: don't hand a small local
      // model an empty context and hope it improvises sensibly — on thin
      // context, the 1.5B model reliably degenerates into paraphrasing its own
      // system instruction back at the user instead of answering. Answer
      // directly instead of invoking generation at all.
      // Casual small talk ("hi", "thanks") never needed notification context
      // in the first place, so it still goes to the model normally.
      if (ragSources.isEmpty && !smallTalk) {
        final name = (await SharedPreferences.getInstance())
                .getString('user_name') ??
            'sir';
        final fallback = _noMatchFallback(name, allNotifications);
        _messages.add(ChatMessage(sender: 'echo', text: fallback));
        emit(
          AskAiMessageReceived(
            messages: List.from(_messages),
            isSearching: false,
          ),
        );
        await memory.add(
          ConversationTurn(
            question: text,
            answer: fallback,
            sourceIds: const [],
            embedding: queryEmbedding,
            at: now,
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
                  content: _clip(e.content, _maxContentChars),
                  when: askTimeLabel(e, now),
                ),
              )
              .join('\n');
      final history = followUp ? memory.historyForPrompt() : null;

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

      final prompt = buildAskAiQwenPrompt(
        text,
        contextString,
        userName,
        now: now,
        history: history,
      );

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
        // Gemini gets a real system instruction and a plain user turn, not
        // the offline model's chat template.
        final stream = GeminiService.instance.generateStream(
          geminiApiKey,
          buildAskAiUserMessage(text, contextString, history: history),
          systemInstruction: getAskAiSystemInstruction(userName, now: now),
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
        // Offline path — this is the only branch that actually needs the model.
        if (modelPath == null) {
          final lastIdx = echoIndex;
          _messages[lastIdx] = _messages[lastIdx].copyWith(
            text:
                "The on-device model isn't installed. Download it in Settings, "
                'or switch to the cloud engine to use Ask Echo without it.',
            isGenerating: false,
          );
          emit(AskAiMessageReceived(messages: List.from(_messages)));
          return;
        }
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

      // Remember the exchange (small talk carries no topic worth following).
      final answer = _messages[echoIndex].text.trim();
      if (!smallTalk && answer.isNotEmpty) {
        await memory.add(
          ConversationTurn(
            question: text,
            answer: answer,
            sourceIds: ragSources.map((e) => e.id).toList(),
            embedding: queryEmbedding,
            at: now,
          ),
        );
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

  static const _maxContentChars = 280;

  static String _clip(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max).trimRight()}…';

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
