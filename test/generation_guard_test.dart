import 'dart:async';

import 'package:fllama/fllama.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/core/services/generation_guard.dart';
import 'package:project_echo/features/echo/data/datasources/briefing_prompt.dart';

const _fast = GenerationLimits(
  firstChunk: Duration(milliseconds: 200),
  stall: Duration(milliseconds: 100),
  total: Duration(seconds: 2),
);

FllamaInferenceRequest _request() => FllamaInferenceRequest(
  contextSize: 16384,
  input: 'prompt',
  maxTokens: 10,
  modelPath: '/model.gguf',
  numGpuLayers: 0,
  penaltyFrequency: 0,
  penaltyRepeat: 1,
  temperature: 0.5,
  topP: 0.9,
);

void main() {
  group('FllamaProgress', () {
    test('passes on only the new text of each callback', () {
      final p = FllamaProgress();
      expect(p.next('Good', '{"x":1}', false), 'Good');
      expect(p.next('Good morning', '{"x":1}', false), ' morning');
      expect(p.next('Good morning', '{"x":1}', true), '');
      expect(p.text, 'Good morning');
    });

    test('an error passed as the final output is a failure', () {
      final p = FllamaProgress();
      expect(
        () => p.next(
          'the request exceeds the available context size',
          '',
          true,
        ),
        throwsA(
          isA<OnDeviceFailure>().having((e) => e.noOutput, 'noOutput', false),
        ),
      );
    });

    test('an error after some output is still a failure', () {
      final p = FllamaProgress();
      p.next('Good morning', '{"x":1}', false);
      expect(
        () => p.next('Error: Unknown exception', '', true),
        throwsA(isA<OnDeviceFailure>()),
      );
    });

    test('finishing with no output is a failure', () {
      expect(
        () => FllamaProgress().next('', '', true),
        throwsA(
          isA<OnDeviceFailure>().having((e) => e.noOutput, 'noOutput', true),
        ),
      );
      expect(
        () => FllamaProgress().next('  \n', '{"x":1}', true),
        throwsA(isA<OnDeviceFailure>()),
      );
    });

    test('a normal ending without JSON keeps what was said', () {
      final p = FllamaProgress();
      p.next('Hello', '{"x":1}', false);
      expect(p.next('Hello', '', true), '');
    });

    test("an error's text never reaches the user-facing message", () {
      const e = OnDeviceFailure('Error: Failed to create inference context');
      expect(e.message, isNot(contains('inference context')));
      expect(friendlyGenerationError(e), e.message);
      expect(
        friendlyGenerationError(Exception('secret prompt text')),
        isNot(contains('secret')),
      );
    });
  });

  group('onDeviceStream', () {
    test('streams the reply and finishes', () async {
      final out = onDeviceStream(
        _request(),
        limits: _fast,
        run: (request, callback) async {
          scheduleMicrotask(() {
            callback('Hi', '{}', false);
            callback('Hi there', '{}', false);
            callback('Hi there', '{}', true);
          });
          return 1;
        },
        cancel: (_) => fail('should not cancel a finished request'),
      );
      expect(await out.join(), 'Hi there');
    });

    test("turns fllama's error output into a stream error", () async {
      final out = onDeviceStream(
        _request(),
        limits: _fast,
        run: (request, callback) async {
          scheduleMicrotask(() => callback('context overflow', '', true));
          return 1;
        },
        cancel: (_) {},
      );
      await expectLater(out, emitsError(isA<OnDeviceFailure>()));
    });

    test('a stall times out and cancels the native request', () async {
      final cancelled = <int>[];
      final out = onDeviceStream(
        _request(),
        limits: _fast,
        run: (request, callback) async {
          scheduleMicrotask(() => callback('Hi', '{}', false));
          return 7;
        },
        cancel: cancelled.add,
      );
      await expectLater(
        out,
        emitsInOrder([
          'Hi',
          emitsError(isA<GenerationTimeout>()),
          emitsDone,
        ]),
      );
      expect(cancelled, [7]);
    });

    test('cancelling the stream cancels the native request', () async {
      final cancelled = <int>[];
      final started = <int>[];
      final sub = onDeviceStream(
        _request(),
        limits: _fast,
        onStarted: started.add,
        run: (request, callback) async => 3,
        cancel: cancelled.add,
      ).listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(started, [3]);
      await sub.cancel();
      expect(cancelled, [3]);
    });

    test('a cancel before fllama hands back an id still reaches it', () async {
      final cancelled = <int>[];
      final id = Completer<int>();
      final sub = onDeviceStream(
        _request(),
        limits: _fast,
        run: (request, callback) => id.future,
        cancel: cancelled.add,
      ).listen((_) {});
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      id.complete(5);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(cancelled, [5]);
    });
  });

  group('guardGeneration', () {
    test('passes a healthy stream through untouched', () async {
      final source = Stream.fromIterable(['a', 'b', 'c']);
      expect(await guardGeneration(source, _fast).toList(), ['a', 'b', 'c']);
    });

    test('fails when nothing arrives in time', () async {
      final never = StreamController<String>();
      await expectLater(
        guardGeneration(never.stream, _fast),
        emitsInOrder([emitsError(isA<GenerationTimeout>()), emitsDone]),
      );
      expect(never.hasListener, isFalse, reason: 'the source is cancelled');
    });

    test('fails when the stream goes quiet part-way', () async {
      final source = StreamController<String>();
      final out = guardGeneration(source.stream, _fast);
      source.add('first');
      await expectLater(
        out,
        emitsInOrder([
          'first',
          emitsError(
            isA<GenerationTimeout>().having((e) => e.overall, 'overall', false),
          ),
          emitsDone,
        ]),
      );
    });

    test('fails when the whole run takes too long', () async {
      const limits = GenerationLimits(
        firstChunk: Duration(milliseconds: 200),
        stall: Duration(milliseconds: 200),
        total: Duration(milliseconds: 250),
      );
      // A chunk every 50ms never stalls, but never ends either.
      final ticking = Stream.periodic(
        const Duration(milliseconds: 50),
        (i) => '$i',
      );
      final events = <Object>[];
      await guardGeneration(ticking, limits)
          .handleError((Object e) => events.add(e))
          .drain<void>();
      expect(
        events.single,
        isA<GenerationTimeout>().having((e) => e.overall, 'overall', true),
      );
    });

    test('forwards a source error and stops', () async {
      final source = StreamController<String>();
      final out = guardGeneration(source.stream, _fast);
      source.addError(StateError('boom'));
      await expectLater(
        out,
        emitsInOrder([emitsError(isA<StateError>()), emitsDone]),
      );
    });
  });

  group('prompt clipping', () {
    test('clipContent leaves short text alone and cuts long text', () {
      expect(clipContent('short'), 'short');
      final long = 'word ' * 200;
      final clipped = clipContent(long);
      expect(clipped.length, lessThanOrEqualTo(maxPromptContentChars + 1));
      expect(clipped, endsWith('…'));
    });

    test('capLines keeps the leading lines that fit', () {
      final lines = ['aaaa', 'bbbb', 'cccc'];
      expect(capLines(lines, 100), lines);
      expect(capLines(lines, 9), ['aaaa', 'bbbb']);
      expect(capLines(lines, 8), ['aaaa']);
      expect(capLines(const [], 10), isEmpty);
      // One line too long for the budget is clipped, not dropped.
      expect(capLines(['a' * 50], 10).single.length, lessThanOrEqualTo(11));
    });

    test('fifteen long emails fit the on-device budget once clipped', () {
      final email = 'Your weekly statement is ready. ${'Lorem ipsum ' * 400}';
      final lines = [
        for (var i = 0; i < 15; i++)
          '[Today] Bank $i (Gmail): ${clipContent(email)}',
      ];
      final overhead = buildQwenPrompt(
        '',
        'Sam',
        includeExample: false,
        now: DateTime(2026, 11, 26, 8),
      ).length;
      final kept = capLines(lines, onDevicePromptCharBudget - overhead);
      final prompt = buildQwenPrompt(
        kept.join('\n'),
        'Sam',
        includeExample: false,
        now: DateTime(2026, 11, 26, 8),
      );
      expect(prompt.length, lessThanOrEqualTo(onDevicePromptCharBudget));
      expect(kept, hasLength(15), reason: "overhead $overhead");
    });
  });
}
