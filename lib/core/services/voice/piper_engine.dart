import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// One spoken sentence: 32-bit float samples at [sampleRate].
class Speech {
  final Float32List samples;
  final int sampleRate;
  const Speech(this.samples, this.sampleRate);
}

/// A Piper voice, run by sherpa-onnx in a background isolate so generating
/// speech never blocks the UI. Requests are answered in order.
class PiperEngine {
  final SendPort _requests;
  final ReceivePort _replies;
  final Isolate _isolate;
  final _waiting = <int, Completer<Speech>>{};
  var _next = 0;

  PiperEngine._(this._requests, this._replies, this._isolate) {
    _replies.listen((message) {
      final (id, bytes, rate) = message as (int, TransferableTypedData?, int);
      final done = _waiting.remove(id);
      if (done == null) return;
      if (bytes == null) {
        done.completeError(StateError('Piper could not speak that'));
      } else {
        done.complete(Speech(bytes.materialize().asFloat32List(), rate));
      }
    });
  }

  /// Starts the voice in [modelDir], whose model is `[name].onnx`.
  static Future<PiperEngine> start(String modelDir, String name) async {
    final ready = ReceivePort();
    final isolate = await Isolate.spawn(_worker, (
      ready.sendPort,
      modelDir,
      name,
    ));
    final first = Completer<SendPort>();
    final replies = ReceivePort();
    ready.listen((message) {
      if (message is SendPort) {
        message.send(replies.sendPort);
        first.complete(message);
      } else if (message is String && !first.isCompleted) {
        first.completeError(StateError(message));
      }
      ready.close();
    });
    try {
      return PiperEngine._(await first.future, replies, isolate);
    } catch (_) {
      replies.close();
      isolate.kill();
      rethrow;
    }
  }

  Future<Speech> speak(String text, {required double speed}) {
    final id = _next++;
    final done = _waiting[id] = Completer<Speech>();
    final took = Stopwatch()..start();
    _requests.send((id, text, speed));
    // How fast it speaks on this phone: below 1 keeps up with playback.
    return done.future.then((speech) {
      final seconds = speech.samples.length / speech.sampleRate;
      debugPrint(
        'Piper: ${seconds.toStringAsFixed(1)} s of speech in '
        '${(took.elapsedMilliseconds / 1000).toStringAsFixed(1)} s',
      );
      return speech;
    });
  }

  void dispose() {
    _isolate.kill(priority: Isolate.immediate);
    _replies.close();
    for (final w in _waiting.values) {
      w.completeError(StateError('Piper stopped'));
    }
    _waiting.clear();
  }

  static void _worker((SendPort, String, String) args) {
    final (ready, dir, name) = args;
    final sherpa.OfflineTts tts;
    try {
      sherpa.initBindings();
      tts = sherpa.OfflineTts(
        sherpa.OfflineTtsConfig(
          model: sherpa.OfflineTtsModelConfig(
            vits: sherpa.OfflineTtsVitsModelConfig(
              model: '$dir/$name.onnx',
              tokens: '$dir/tokens.txt',
              dataDir: '$dir/espeak-ng-data',
            ),
            numThreads: 2,
            debug: false,
          ),
        ),
      );
      // The first sentence is always the slowest; get it out of the way.
      tts.generate(text: 'Hi.');
    } catch (e) {
      ready.send('$e');
      return;
    }
    final requests = ReceivePort();
    ready.send(requests.sendPort);
    late SendPort replies;
    requests.listen((message) {
      if (message is SendPort) {
        replies = message;
        return;
      }
      final (id, text, speed) = message as (int, String, double);
      try {
        final audio = tts.generate(text: text, speed: speed);
        replies.send((
          id,
          TransferableTypedData.fromList([audio.samples]),
          audio.sampleRate,
        ));
      } catch (_) {
        replies.send((id, null, 0));
      }
    });
  }
}
