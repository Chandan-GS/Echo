import 'dart:async';
import 'dart:io';

import 'package:fllama/fllama.dart';
import 'package:flutter/foundation.dart';
import 'package:project_echo/core/services/desktop_engine_client.dart';
import 'package:project_echo/core/services/gemini_service.dart';
import 'package:project_echo/core/services/offline_model_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where a piece of writing will be done, worked out fresh for each request.
sealed class WritingRoute {
  const WritingRoute();
}

class WriteOnComputer extends WritingRoute {
  final String host;
  const WriteOnComputer(this.host);
}

class WriteWithGemini extends WritingRoute {
  final String apiKey;
  const WriteWithGemini(this.apiKey);
}

class WriteOnPhone extends WritingRoute {
  final String modelPath;
  const WriteOnPhone(this.modelPath);
}

class NoWritingRoute extends WritingRoute {
  /// The owner chose their computer, and it couldn't be reached.
  final bool computerWanted;
  const NoWritingRoute({this.computerWanted = false});
}

/// A computer that answered first, then Gemini if it's switched on with a
/// key, then the model on this phone.
WritingRoute pickWritingRoute({
  required String? reachableComputer,
  required bool computerWanted,
  required bool offlineEngine,
  required String geminiKey,
  required String? modelPath,
}) {
  if (reachableComputer != null) return WriteOnComputer(reachableComputer);
  if (!offlineEngine && geminiKey.isNotEmpty) return WriteWithGemini(geminiKey);
  if (modelPath != null) return WriteOnPhone(modelPath);
  return NoWritingRoute(computerWanted: computerWanted);
}

/// The route the current settings lead to. The computer check is bounded to
/// about a second, so a sleeping computer never noticeably delays anything.
/// Desktop builds never offload to another desktop engine.
Future<WritingRoute> currentWritingRoute(SharedPreferences prefs) async {
  final computerWanted =
      !(Platform.isMacOS || Platform.isWindows) &&
      (prefs.getBool('prefer_desktop_engine') ?? false);
  String? host;
  if (computerWanted) {
    host = await DesktopEngineClient.discoverHost(
      cachedHost: prefs.getString('desktop_engine_host'),
    );
    if (host != null) await prefs.setString('desktop_engine_host', host);
  }
  if (host != null) return WriteOnComputer(host);
  return pickWritingRoute(
    reachableComputer: null,
    computerWanted: computerWanted,
    offlineEngine: prefs.getBool('is_offline_engine') ?? true,
    geminiKey: prefs.getString('gemini_api_key') ?? '',
    modelPath: await createOfflineModelRepository().downloadedPathOrNull(),
  );
}

/// What to write: Gemini takes the two parts separately, the local models
/// take them in Qwen's chat template.
class WritingPrompt {
  final String system;
  final String user;
  const WritingPrompt({required this.system, required this.user});

  String get chatTemplate =>
      '<|im_start|>system\n$system<|im_end|>\n'
      '<|im_start|>user\n$user<|im_end|>\n'
      '<|im_start|>assistant\n';
}

/// Chat-template tokens a local model sometimes leaves in its output.
String withoutChatTokens(String text) => text
    .replaceAll(RegExp(r'<\|im_start\|>.*', dotAll: true), '')
    .replaceAll(RegExp(r'<\|[^|]*\|>'), '')
    .trim();

/// Stops a piece of writing from outside its stream.
class WritingCancel {
  VoidCallback? _stop;
  var _cancelled = false;

  void cancel() {
    _cancelled = true;
    _stop?.call();
  }
}

/// The writing as it streams in, piece by piece, from [route]. Failures reach
/// the listener: a [GeminiFailure], or the computer's connection error.
Stream<String> writeWith(
  WritingRoute route,
  WritingPrompt prompt, {
  required int maxTokens,
  required double temperature,
  WritingCancel? cancel,
}) async* {
  switch (route) {
    case WriteOnComputer(:final host):
      yield* DesktopEngineClient.generateStream(
        host: host,
        endpoint: 'ask',
        prompt: prompt.chatTemplate,
      );
    case WriteWithGemini(:final apiKey):
      await for (final response in GeminiService.instance.generateStream(
        apiKey,
        prompt.user,
        systemInstruction: prompt.system,
      )) {
        final chunk = response.text ?? '';
        if (chunk.isNotEmpty) yield chunk;
      }
    case WriteOnPhone(:final modelPath):
      yield* OnPhoneWriter.run(
        FllamaInferenceRequest(
          // fllama splits the context across parallel slots, so the usable
          // window is only contextSize / n_parallel. 16384 keeps the usable
          // slot at ~2048+ tokens, and keeping it identical to the briefing
          // request lets the loaded model be reused instead of reloaded when
          // switching between them.
          contextSize: 16384,
          input: prompt.chatTemplate,
          maxTokens: maxTokens,
          modelPath: modelPath,
          numGpuLayers: 99,
          numThreads: 4,
          temperature: temperature,
          penaltyFrequency: 0.0,
          penaltyRepeat: 1.1,
          topP: 0.9,
        ),
        cancel: cancel,
      );
    case NoWritingRoute():
      break;
  }
}

/// Runs the on-device model one request at a time. fllama keeps the model
/// loaded for the life of the app and runs it on its own thread, so nothing
/// here touches the UI; taking turns keeps a draft and an Ask answer from
/// splitting a small phone's memory and CPU between them. A turn ends when
/// the request finishes, is cancelled, or its listener leaves.
class OnPhoneWriter {
  OnPhoneWriter._();

  static Future<void> _turn = Future.value();

  @visibleForTesting
  static Future<int> Function(FllamaInferenceRequest, FllamaInferenceCallback)
  startInference = fllamaInference;

  @visibleForTesting
  static void Function(int) cancelInference = fllamaCancelInference;

  static Stream<String> run(
    FllamaInferenceRequest request, {
    WritingCancel? cancel,
  }) {
    final out = StreamController<String>();
    final ahead = _turn;
    final mine = Completer<void>();
    _turn = mine.future;

    int? id;
    var finished = false;
    var sent = 0;

    void finish() {
      if (finished) return;
      finished = true;
      mine.complete();
      out.close();
    }

    void stop() {
      if (finished) return;
      if (id != null) cancelInference(id!);
      finish();
    }

    out.onCancel = stop;
    cancel?._stop = stop;

    () async {
      await ahead;
      if (finished) return;
      if (cancel?._cancelled ?? false) return finish();
      try {
        final started = await startInference(request, (
          cumulative,
          openaiJson,
          isDone,
        ) {
          if (finished) return;
          if (cumulative.length > sent) {
            out.add(cumulative.substring(sent));
            sent = cumulative.length;
          }
          if (isDone) finish();
        });
        // Stopped while it was starting.
        if (finished) return cancelInference(started);
        id = started;
      } catch (e) {
        if (finished) return;
        out.addError(e);
        finish();
      }
    }();

    return out.stream;
  }
}
