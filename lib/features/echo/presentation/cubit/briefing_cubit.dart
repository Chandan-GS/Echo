import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:project_echo/core/services/analytics_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fllama/fllama.dart';
import 'package:project_echo/features/echo/data/datasources/briefing_prompt.dart';
import 'package:project_echo/features/onboarding/data/onboarding_personalization.dart';
import 'package:project_echo/features/echo/data/datasources/priority_query_embedding.dart';
import 'package:project_echo/features/echo/data/relevance/briefing_selection.dart';
import 'package:project_echo/features/echo/data/relevance/temporal_relevance.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/core/services/gemini_service.dart';
import 'package:project_echo/core/services/widget_refresh_service.dart';
import 'package:project_echo/core/services/phone_sync_service.dart';
import 'package:project_echo/core/services/desktop_engine_client.dart';
import 'package:project_echo/core/services/offline_model_repository.dart';

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
        // Normally a cached briefing just sits there for the user to tap
        // "Play Today's Briefing" (BriefingCached). But if we got here because
        // the user tapped the notification/widget's tap-to-play (see
        // EchoHomeScreen's listener, which reads-and-clears this same flag),
        // skip straight to BriefingReady so the existing auto-navigate +
        // autoplay path actually fires instead of silently doing nothing.
        final autoPlay = prefs.getBool('pending_autoplay') ?? false;
        final ttsText = stripForTts(rawText);
        if (autoPlay) {
          emit(BriefingReady(rawText: rawText, ttsText: ttsText));
        } else {
          emit(BriefingCached(rawText: rawText, ttsText: ttsText));
        }
      }
    } catch (_) {}
  }

  void playCachedBriefing(String rawText) {
    emit(BriefingReady(rawText: rawText, ttsText: stripForTts(rawText)));
  }

  /// [attempt] is used internally to retry once when the on-device model
  /// returns an empty response — the first inference right after the model is
  /// (re)loaded can occasionally come back blank, and a single retry against
  /// the now-warm model reliably produces a briefing.
  Future<void> generateBriefing({int attempt = 0}) async {
    // Count feature usage only on the initial trigger, not internal retries.
    if (attempt == 0) Analytics.track('briefing_generated');

    // Cancel any in-flight generation stream so a stale "Regenerate" run can't
    // fire its onDone and overwrite the new run's state.
    await _streamSub?.cancel();
    _streamSub = null;

    emit(BriefingGenerating());

    try {
      // The on-device model is only needed for the offline (Fllama) path below.
      // Cloud (Gemini) and desktop-engine paths don't require it, so we no
      // longer hard-gate here — the offline branch guards on modelPath itself.
      final modelPath = await createOfflineModelRepository().downloadedPathOrNull();

      // ── 2. Pick what's relevant from now until the end of tomorrow ────────
      final now = DateTime.now();
      final entries = await IsarDataSource.getAllEntries();
      if (entries.isEmpty) {
        emit(BriefingError('No important notifications available.'));
        return;
      }

      final notificationContext = await _buildContext(entries, now);
      if (notificationContext == null) {
        const clearSchedule =
            'Echo: Nothing needs your attention today or tomorrow. Enjoy the clear schedule!';
        emit(BriefingReady(rawText: clearSchedule, ttsText: clearSchedule));
        return;
      }

      // ── 3. REDUCE PHASE: Final briefing generation ────────────────────────
      emit(BriefingGenerating(partial: 'Synthesizing briefing...'));

      final prefs = await SharedPreferences.getInstance();
      final isOfflineEngine = prefs.getBool('is_offline_engine') ?? true;
      final geminiApiKey = prefs.getString('gemini_api_key') ?? '';
      final userName = prefs.getString('user_name') ?? 'Sir';
      final tone = onboardingToneFromId(prefs.getString('briefing_tone'));

      // Phone-first, computer-optional: if the user has opted in and a
      // desktop Echo Engine is actually reachable right now, prefer it over
      // both the on-device and Gemini paths. This check is bounded to well
      // under a second so a missing/off desktop never noticeably delays
      // generation — it just falls through to the existing behavior. Desktop
      // builds never do this at all — this computer already generates
      // locally, so "prefer a computer" only ever makes sense on a phone. A
      // desktop build with a stale prefer_desktop_engine=true (e.g. leftover
      // from testing) would otherwise discover and call itself over HTTP.
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
          rawText = separateListItems(rawText);
          rawText = autoBold(rawText);
          rawText = sanitizeBoldMarkup(rawText);

          print(
            '=== ECHO GENERATED OUTPUT ===\n$rawText\n=============================',
          );

          if (rawText.isEmpty) {
            // The on-device model's first inference after a (re)load can come
            // back blank; retry once against the now-warm model before failing.
            if (isOfflineEngine && attempt == 0) {
              if (!done.isCompleted) done.complete();
              generateBriefing(attempt: 1);
              return;
            }
            emit(BriefingError('The model produced an empty response.'));
          } else {
            final ttsText = stripForTts(rawText);
            try {
              final prefs = await SharedPreferences.getInstance();
              final today = DateTime.now().toIso8601String().split('T').first;
              await prefs.setString('cached_briefing_date', today);
              await prefs.setString('cached_briefing_text', rawText);
              // Best-effort: no-ops when this runs in the headless alarm
              // isolate (no Activity to receive it) — the widget's own
              // periodic tick covers that case instead.
              WidgetRefreshService.refresh();
              // Push the fresh briefing to a connected computer, if any.
              PhoneSyncService.instance.syncNow();
            } catch (_) {}
            emit(BriefingReady(rawText: rawText, ttsText: ttsText));
          }
          if (!done.isCompleted) done.complete();
        },
      );

      final prompt = buildQwenPrompt(
        notificationContext,
        userName,
        toneInstruction: tone.promptInstruction,
        // Only the small on-device phone model copies the few-shot example
        // verbatim; the stronger cloud and desktop-engine models handle it
        // fine (and generate a better-shaped briefing with it).
        includeExample: useDesktopEngine || !isOfflineEngine,
        now: now,
      );

      _debugPrintLongString(
        '=== LLM INPUT PROMPT ===\n$prompt\n========================',
      );

      if (useDesktopEngine) {
        final stream = DesktopEngineClient.generateStream(
          host: desktopHost,
          endpoint: 'briefing',
          prompt: prompt,
        );
        stream.listen(
          (chunk) {
            if (chunk.isNotEmpty) controller.add(chunk);
          },
          onDone: () => controller.close(),
          onError: (e) => controller.addError(e),
        );
      } else if (!isOfflineEngine && geminiApiKey.isNotEmpty) {
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
        // Offline path — this is the only branch that actually needs the model.
        if (modelPath == null) {
          await _streamSub?.cancel();
          _streamSub = null;
          if (!done.isCompleted) done.complete();
          await controller.close();
          emit(
            BriefingError(
              "The on-device model isn't installed. Download it in Settings, "
              'or switch to the cloud engine to generate without it.',
            ),
          );
          return;
        }
        final request = FllamaInferenceRequest(
          // fllama runs a llama.cpp server that splits the context across
          // parallel slots, so the usable per-request window is only
          // contextSize / n_parallel. 16384 keeps each briefing's slot at
          // ~2048+ tokens even in the worst case — comfortably fitting the
          // system prompt + trimmed notification context + the output.
          // NOTE: the native model is cached for the app's lifetime and only
          // reloads when this value changes AND the process restarts; a hot
          // reload alone will keep using the previously-loaded context size.
          contextSize: 16384,
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

  /// The briefing's notification context at [now]: everything relevant from
  /// now until the end of tomorrow, one line each, labelled with when it
  /// applies. Null when nothing qualifies.
  Future<String?> _buildContext(List<RawData> entries, DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    // The on-device model's context window is small; cloud and desktop
    // engines can take a fuller day.
    final onDevice = prefs.getBool('is_offline_engine') ?? true;
    final aliases = Map<String, String>.from(
      jsonDecode(prefs.getString('vault_category_aliases') ?? '{}'),
    );
    final blocked = prefs.getStringList('vault_blocked_categories') ?? [];

    // Desktop mirrors notifications from the phone WITHOUT embeddings (the
    // sync payload omits the 384-float vectors, and TensorFlow Lite isn't
    // available here to recompute them), so undated items are ranked by
    // recency there instead of by priority similarity.
    final isDesktop = Platform.isMacOS || Platform.isWindows;
    final items = selectForBriefing(
      entries,
      now,
      aliases: aliases,
      blockedCategories: blocked,
      priorityVector: isDesktop ? null : priorityQueryEmbedding,
      limit: onDevice ? 15 : 25,
    );
    if (items.isEmpty) return null;

    return items
        .map(
          (i) => formatNotification(
            source: i.entry.source,
            sender: i.entry.sender,
            content: rewriteRelativeDays(i.entry.content, i.entry.timestamp, now),
            when: describeEntry(i.entry, i.window, now),
          ),
        )
        .join('\n');
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
