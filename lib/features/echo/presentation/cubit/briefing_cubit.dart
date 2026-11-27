import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:project_echo/core/services/analytics_service.dart';
import 'package:project_echo/core/services/pending_autoplay.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fllama/fllama.dart';
import 'package:project_echo/features/echo/data/context/chat_context_store.dart';
import 'package:project_echo/features/echo/data/datasources/briefing_prompt.dart';
import 'package:project_echo/features/onboarding/data/onboarding_personalization.dart';
import 'package:project_echo/features/echo/data/datasources/priority_query_embedding.dart';
import 'package:project_echo/features/echo/data/relevance/briefing_selection.dart';
import 'package:project_echo/features/echo/data/relevance/temporal_relevance.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/core/services/gemini_service.dart';
import 'package:project_echo/core/services/gemini_usage.dart';
import 'package:project_echo/core/services/generation_guard.dart';
import 'package:project_echo/core/services/widget_refresh_service.dart';
import 'package:project_echo/core/services/phone_sync_service.dart';
import 'package:project_echo/core/services/desktop_engine_client.dart';
import 'package:project_echo/core/services/offline_model_repository.dart';
import 'package:project_echo/features/echo/data/services/notification_ingest.dart';
import 'package:project_echo/features/vault/data/app_access.dart';

part 'briefing_state.dart';

class BriefingCubit extends Cubit<BriefingState> {
  StreamSubscription<String>? _streamSub;

  /// Bumped by every new generation and by [goBack], so a run that was
  /// superseded or abandoned mid-way never emits over what came after it.
  int _run = 0;

  BriefingCubit() : super(BriefingInitial()) {
    loadCachedBriefing();
  }

  /// Emits [s] unless the cubit is closed or [run] is no longer current.
  void _emitFor(int run, BriefingState s) {
    if (isClosed || run != _run) return;
    emit(s);
  }

  Future<void> loadCachedBriefing() async {
    final run = _run;
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
        // A generation started meanwhile wins ([_emitFor] drops this).
        final autoPlay = PendingAutoplay.isPending(prefs);
        final ttsText = stripForTts(rawText);
        if (autoPlay) {
          _emitFor(run, BriefingReady(rawText: rawText, ttsText: ttsText));
        } else {
          _emitFor(run, BriefingCached(rawText: rawText, ttsText: ttsText));
        }
      }
    } catch (_) {}
  }

  void playCachedBriefing(String rawText) {
    if (isClosed) return;
    emit(BriefingReady(rawText: rawText, ttsText: stripForTts(rawText)));
  }

  /// [attempt] is used internally to retry once when the on-device model
  /// returns an empty response — the first inference right after the model is
  /// (re)loaded can occasionally come back blank, and a single retry against
  /// the now-warm model reliably produces a briefing.
  ///
  /// Every engine's reply is bounded (see [GenerationLimits]); a failure of
  /// any kind, including fllama's errors that arrive dressed as output, ends
  /// in [BriefingError] and is never cached, notified or spoken.
  Future<void> generateBriefing({int attempt = 0}) async {
    // Count feature usage only on the initial trigger, not internal retries.
    if (attempt == 0) Analytics.track('briefing_generated');

    // Cancel any in-flight generation stream so a stale "Regenerate" run can't
    // fire its onDone and overwrite the new run's state.
    await _streamSub?.cancel();
    _streamSub = null;

    final run = ++_run;
    bool current() => !isClosed && run == _run;

    _emitFor(run, BriefingGenerating());

    try {
      // The on-device model is only needed for the offline (Fllama) path below.
      // Cloud (Gemini) and desktop-engine paths don't require it, so we no
      // longer hard-gate here — the offline branch guards on modelPath itself.
      final modelPath = await createOfflineModelRepository()
          .downloadedPathOrNull();

      // ── 2. Pick what's relevant from now until the end of tomorrow ────────
      // Notifications missed while the app was closed first, with their
      // embeddings if they come in time (they rank what's kept).
      await NotificationIngest.whenCaughtUp();
      await EmbeddingBackfill.whenDone().timeout(
        const Duration(seconds: 15),
        onTimeout: () {},
      );
      final now = DateTime.now();
      final entries = await IsarDataSource.getAllEntries();
      if (entries.isEmpty) {
        _emitFor(run, BriefingError('No important notifications available.'));
        return;
      }

      final lines = await _buildContext(entries, now);
      if (lines == null) {
        const clearSchedule =
            'Echo: Nothing needs your attention today or tomorrow. Enjoy the clear schedule!';
        _emitFor(
          run,
          BriefingReady(rawText: clearSchedule, ttsText: clearSchedule),
        );
        return;
      }

      // ── 3. REDUCE PHASE: Final briefing generation ────────────────────────
      _emitFor(run, BriefingGenerating(partial: 'Writing your briefing…'));

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
      final preferDesktopEngine =
          !(Platform.isMacOS || Platform.isWindows) &&
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
      final useGemini =
          !useDesktopEngine && !isOfflineEngine && geminiApiKey.isNotEmpty;
      final onDevice = !useDesktopEngine && !useGemini;

      String promptFor(String context) => buildQwenPrompt(
        context,
        userName,
        toneInstruction: tone.promptInstruction,
        // Only the small on-device phone model copies the few-shot example
        // verbatim; the stronger cloud and desktop-engine models handle it
        // fine (and generate a better-shaped briefing with it).
        includeExample: useDesktopEngine || !isOfflineEngine,
        now: now,
      );

      // The on-device model (and a desktop engine, which runs the same one)
      // has a 4096-token slot for the prompt and the briefing together, so
      // the notifications are cut to what fits, least important last.
      final kept = useGemini
          ? lines
          : capLines(lines, onDevicePromptCharBudget - promptFor('').length);
      final prompt = promptFor(kept.join('\n'));
      _log(
        'Briefing prompt: ${prompt.length} chars, '
        '${kept.length} of ${lines.length} notifications',
      );

      // Gone back (or a newer run started) while the context was built:
      // don't start a generation nobody is waiting for.
      if (!current()) return;

      final Stream<String> reply;
      if (useDesktopEngine) {
        reply = DesktopEngineClient.generateStream(
          host: desktopHost,
          endpoint: 'briefing',
          prompt: prompt,
        );
      } else if (useGemini) {
        reply = GeminiService.instance
            .generateStream(geminiApiKey, prompt)
            .map((response) => response.text ?? '');
      } else {
        // Offline path — this is the only branch that actually needs the model.
        if (modelPath == null) {
          _emitFor(
            run,
            BriefingError(
              "The on-device model isn't installed. Download it in Settings, "
              'or switch to the cloud engine to generate without it.',
            ),
          );
          return;
        }
        reply = onDeviceStream(
          FllamaInferenceRequest(
            // fllama runs a llama.cpp server that splits the context across
            // parallel slots, so the usable per-request window is only
            // contextSize / n_parallel (4), i.e. 4096 tokens — which is why
            // the prompt is capped above.
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
          ),
        );
      }

      final buffer = StringBuffer();
      final done = Completer<void>();
      void finish() {
        if (!done.isCompleted) done.complete();
      }

      _streamSub = reply.listen(
        buffer.write,
        cancelOnError: true,
        onError: (Object err) {
          _log('Briefing generation failed (${err.runtimeType})');
          // The on-device model's first inference after a (re)load can come
          // back blank; retry once against the now-warm model before failing.
          if (onDevice &&
              attempt == 0 &&
              err is OnDeviceFailure &&
              err.noOutput &&
              current()) {
            finish();
            generateBriefing(attempt: 1);
            return;
          }
          _emitFor(
            run,
            BriefingError(
              err is GeminiFailure ? err.message : friendlyGenerationError(err),
              limitReached:
                  err is GeminiFailure &&
                  err.hit?.kind == GeminiLimitKind.perDay,
            ),
          );
          finish();
        },
        onDone: () async {
          try {
            if (!current()) return;
            final rawText = cleanBriefingOutput(buffer.toString());
            _log('Briefing reply: ${rawText.length} chars');

            if (rawText.isEmpty) {
              if (onDevice && attempt == 0) {
                finish();
                generateBriefing(attempt: 1);
                return;
              }
              _emitFor(
                run,
                BriefingError('The model produced an empty response.'),
              );
              return;
            }
            final ttsText = stripForTts(rawText);
            try {
              final prefs = await SharedPreferences.getInstance();
              final today = DateTime.now().toIso8601String().split('T').first;
              await prefs.setString('cached_briefing_date', today);
              await prefs.setString(
                'cached_briefing_time',
                DateTime.now().toIso8601String(),
              );
              await prefs.setString('cached_briefing_text', rawText);
              // Best-effort: no-ops when this runs in the headless alarm
              // isolate (no Activity to receive it) — the widget's own
              // periodic tick covers that case instead.
              WidgetRefreshService.refresh();
              // Push the fresh briefing to a connected computer, if any.
              PhoneSyncService.instance.syncNow();
            } catch (_) {}
            _emitFor(run, BriefingReady(rawText: rawText, ttsText: ttsText));
          } finally {
            finish();
          }
        },
      );

      await done.future;
    } catch (e) {
      _log('Briefing failed (${e.runtimeType})');
      _emitFor(
        run,
        BriefingError(
          e is GeminiFailure ? e.message : friendlyGenerationError(e),
        ),
      );
    }
  }

  /// The briefing's notification lines at [now]: everything relevant from
  /// now until the end of tomorrow, one line each (its text clipped to
  /// [maxPromptContentChars]), labelled with when it applies, most important
  /// kept first. Null when nothing qualifies.
  Future<List<String>?> _buildContext(List<RawData> entries, DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    // The on-device model's context window is small; cloud and desktop
    // engines can take a fuller day.
    final onDevice = prefs.getBool('is_offline_engine') ?? true;
    final aliases = Map<String, String>.from(
      jsonDecode(prefs.getString('vault_category_aliases') ?? '{}'),
    );
    // Blocked categories, and apps switched off in Apps Echo hears.
    final excluded = await loadExcludedSources();

    // Desktop mirrors notifications from the phone WITHOUT embeddings (the
    // sync payload omits the 384-float vectors, and TensorFlow Lite isn't
    // available here to recompute them), so undated items are ranked by
    // recency there instead of by priority similarity.
    final isDesktop = Platform.isMacOS || Platform.isWindows;
    final items = selectForBriefing(
      entries,
      now,
      aliases: aliases,
      blockedCategories: excluded.toList(),
      priorityVector: isDesktop ? null : priorityQueryEmbedding,
      affinity: (await ChatContextStore.loadEngagement()).affinity,
      limit: onDevice ? 15 : 25,
    );
    if (items.isEmpty) return null;

    final myTurns = await ChatContextStore.loadMyTurns();
    return [
      for (final i in items)
        formatEntry(
          i.entry,
          content: clipContent(
            rewriteRelativeDays(i.entry.content, i.entry.timestamp, now),
          ),
          when: describeEntry(i.entry, i.window, now),
          myTurns: myTurns,
        ),
    ];
  }

  /// Goes back from the briefing, stopping a generation in progress (and the
  /// native request behind it).
  Future<void> goBack() async {
    final run = ++_run;
    _stopStream();

    try {
      final prefs = await SharedPreferences.getInstance();
      final dateStr = prefs.getString('cached_briefing_date');
      final rawText = prefs.getString('cached_briefing_text');

      final today = DateTime.now().toIso8601String().split('T').first;
      if (dateStr == today && rawText != null && rawText.isNotEmpty) {
        _emitFor(
          run,
          BriefingCached(rawText: rawText, ttsText: stripForTts(rawText)),
        );
        return;
      }
    } catch (_) {}

    _emitFor(run, BriefingInitial());
  }

  /// Stops the generation in progress without waiting for it to wind down.
  void _stopStream() {
    final sub = _streamSub;
    _streamSub = null;
    if (sub != null) unawaited(sub.cancel());
  }

  void resetBriefing() {
    goBack();
  }

  /// Debug builds only, and never the prompt or the briefing itself: they
  /// carry people's messages.
  static void _log(String message) {
    if (kDebugMode) debugPrint(message);
  }

  @override
  Future<void> close() async {
    _run++;
    _stopStream();
    return super.close();
  }
}

/// The model's raw briefing tidied for showing and speaking: chat-template
/// tokens dropped, sign-offs, repeats and filler cut, lists split and key
/// details bolded.
String cleanBriefingOutput(String output) {
  var rawText = output
      .trim()
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
  return rawText;
}
