import 'dart:async';

import 'package:fllama/fllama.dart';

/// A generation that went quiet or ran too long, so it was given up on. The
/// message is safe to show as is.
class GenerationTimeout implements Exception {
  /// Whether the whole run hit its ceiling, rather than going quiet.
  final bool overall;

  const GenerationTimeout({this.overall = false});

  String get message => overall
      ? 'That took too long, so I stopped. Try again in a moment.'
      : 'The model stopped responding. Try again in a moment.';

  @override
  String toString() => message;
}

/// The on-device model failed: fllama reports its errors (a prompt too long
/// for the context, a model that wouldn't load) as if they were the output,
/// so they're caught here and never shown, cached or spoken. [detail] is
/// fllama's own text, for debugging only.
class OnDeviceFailure implements Exception {
  final String detail;

  /// The run ended without a word, rather than with an error. The first run
  /// after the model (re)loads sometimes does; a second try usually works.
  final bool noOutput;

  const OnDeviceFailure(this.detail, {this.noOutput = false});

  String get message => noOutput
      ? 'The model produced an empty response.'
      : "The on-device model couldn't finish that. Try again in a moment.";

  @override
  String toString() => message;
}

/// What to tell the user when a generation fails with [error]: the error's
/// own wording when it's one of ours, never raw exception text (which can
/// carry hosts, paths or fragments of the prompt).
String friendlyGenerationError(Object error) => switch (error) {
  GenerationTimeout e => e.message,
  OnDeviceFailure e => e.message,
  _ => "Something went wrong while writing that. Try again in a moment.",
};

/// How long a generation may take: [firstChunk] to say anything at all
/// (loading a model and reading a long prompt are slow), [stall] between
/// pieces once it's talking, and [total] for the whole run.
class GenerationLimits {
  final Duration firstChunk;
  final Duration stall;
  final Duration total;

  const GenerationLimits({
    required this.firstChunk,
    required this.stall,
    required this.total,
  });

  /// Gemini answers within seconds when it's working.
  static const gemini = GenerationLimits(
    firstChunk: Duration(seconds: 45),
    stall: Duration(seconds: 30),
    total: Duration(minutes: 3),
  );

  /// The phone's own model: the first piece waits on the model loading and
  /// a slow phone reading a full prompt.
  static const onDevice = GenerationLimits(
    firstChunk: Duration(minutes: 3),
    stall: Duration(seconds: 45),
    total: Duration(minutes: 8),
  );

  /// A desktop engine, which may itself have to load its model first.
  static const desktop = GenerationLimits(
    firstChunk: Duration(minutes: 3),
    stall: Duration(seconds: 45),
    total: Duration(minutes: 8),
  );

  GenerationLimits copyWith({Duration? total}) => GenerationLimits(
    firstChunk: firstChunk,
    stall: stall,
    total: total ?? this.total,
  );
}

/// [source], failing with a [GenerationTimeout] when it says nothing within
/// [GenerationLimits.firstChunk], goes quiet for longer than
/// [GenerationLimits.stall], or runs past [GenerationLimits.total]. On a
/// timeout or an error the source is cancelled, which is what stops the work
/// behind it (an HTTP request, a native inference). Cancelling the result
/// cancels the source too.
Stream<T> guardGeneration<T>(Stream<T> source, GenerationLimits limits) {
  late final StreamController<T> out;
  StreamSubscription<T>? sub;
  Timer? gap;
  Timer? overall;

  void stopTimers() {
    gap?.cancel();
    overall?.cancel();
  }

  void finish([Object? error, StackTrace? stack]) {
    stopTimers();
    if (out.isClosed) return;
    if (error != null) out.addError(error, stack);
    out.close();
  }

  void fail(Object error, [StackTrace? stack]) {
    final s = sub;
    sub = null;
    s?.cancel();
    finish(error, stack);
  }

  out = StreamController<T>(
    onListen: () {
      overall = Timer(
        limits.total,
        () => fail(const GenerationTimeout(overall: true)),
      );
      gap = Timer(limits.firstChunk, () => fail(const GenerationTimeout()));
      sub = source.listen(
        (chunk) {
          if (out.isClosed) return;
          gap?.cancel();
          gap = Timer(limits.stall, () => fail(const GenerationTimeout()));
          out.add(chunk);
        },
        onError: fail,
        onDone: () {
          sub = null;
          finish();
        },
      );
    },
    onCancel: () {
      stopTimers();
      final s = sub;
      sub = null;
      return s?.cancel();
    },
  );
  return out.stream;
}

/// Turns fllama's callbacks into new text, spotting its errors. fllama
/// always passes the whole output so far; it reports a failure as a final
/// callback whose text is the error message and whose OpenAI JSON is empty,
/// and a run that ends without a word is a failure too.
class FllamaProgress {
  String _sent = '';

  /// Everything taken as output so far.
  String get text => _sent;

  /// The new text in this callback, or '' when there's none. Throws an
  /// [OnDeviceFailure] when the callback is an error, or the run finished
  /// with nothing.
  String next(String cumulative, String openaiJson, bool done) {
    if (done && openaiJson.isEmpty && cumulative != _sent) {
      throw OnDeviceFailure(cumulative);
    }
    var delta = '';
    if (cumulative.length > _sent.length && cumulative.startsWith(_sent)) {
      delta = cumulative.substring(_sent.length);
      _sent = cumulative;
    }
    if (done && _sent.trim().isEmpty) {
      throw const OnDeviceFailure('finished without output', noOutput: true);
    }
    return delta;
  }
}

typedef FllamaRun =
    Future<int> Function(
      FllamaInferenceRequest request,
      FllamaInferenceCallback callback,
    );

/// The on-device model's reply to [request], piece by piece, with its errors
/// as stream errors (see [FllamaProgress]) and [limits] applied. Cancelling
/// the stream, or a timeout, cancels the native request. [onStarted] gets the
/// native request id once there is one, for callers that cancel it
/// themselves; [run] and [cancel] stand in for fllama in tests.
Stream<String> onDeviceStream(
  FllamaInferenceRequest request, {
  GenerationLimits limits = GenerationLimits.onDevice,
  void Function(int requestId)? onStarted,
  FllamaRun run = fllamaInference,
  void Function(int requestId) cancel = fllamaCancelInference,
}) {
  final progress = FllamaProgress();
  int? requestId;
  var stopped = false;
  var finished = false;
  late final StreamController<String> pieces;

  void stopNative() {
    if (stopped) return;
    stopped = true;
    final id = requestId;
    if (id != null && !finished) cancel(id);
  }

  pieces = StreamController<String>(
    onListen: () async {
      try {
        final id = await run(request, (cumulative, openaiJson, done) {
          if (pieces.isClosed) return;
          if (done) finished = true;
          try {
            final delta = progress.next(cumulative, openaiJson, done);
            if (delta.isNotEmpty) pieces.add(delta);
            if (done) pieces.close();
          } on OnDeviceFailure catch (e) {
            pieces.addError(e);
            pieces.close();
          }
        });
        requestId = id;
        // Cancelled before fllama handed back an id.
        if (stopped && !finished) {
          cancel(id);
        } else if (!finished) {
          onStarted?.call(id);
        }
      } catch (e) {
        if (!pieces.isClosed) {
          pieces.addError(OnDeviceFailure('$e'));
          pieces.close();
        }
      }
    },
    onCancel: stopNative,
  );
  return guardGeneration(pieces.stream, limits);
}
