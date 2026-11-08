import 'dart:async';

import 'package:fllama/fllama.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/core/services/writing_engine.dart';
import 'package:project_echo/features/echo/data/ask/ask_intents.dart';
import 'package:project_echo/features/echo/data/datasources/briefing_prompt.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/reply/reply_drafter.dart';
import 'package:shared_preferences/shared_preferences.dart';

RawData _message() => RawData()
  ..source = 'WhatsApp'
  ..sender = 'Rohan'
  ..content = 'Coorg on Friday?'
  ..timestamp = DateTime(2026, 11, 8, 10);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('pickWritingRoute', () {
    WritingRoute pick({
      String? computer,
      bool wanted = false,
      bool offline = true,
      String key = '',
      String? model,
    }) => pickWritingRoute(
      reachableComputer: computer,
      computerWanted: wanted,
      offlineEngine: offline,
      geminiKey: key,
      modelPath: model,
    );

    test('a reachable computer comes first', () {
      expect(
        pick(computer: 'h:1', offline: false, key: 'k', model: 'm'),
        isA<WriteOnComputer>(),
      );
    });

    test('Gemini needs the setting and a key', () {
      expect(pick(offline: false, key: 'k', model: 'm'), isA<WriteWithGemini>());
      expect(pick(offline: true, key: 'k', model: 'm'), isA<WriteOnPhone>());
      expect(pick(offline: false, model: 'm'), isA<WriteOnPhone>());
    });

    test('nothing available says whether the computer was the plan', () {
      expect((pick() as NoWritingRoute).computerWanted, isFalse);
      expect((pick(wanted: true) as NoWritingRoute).computerWanted, isTrue);
    });

    test('a sleeping computer falls through to the phone', () {
      expect(pick(wanted: true, model: 'm'), isA<WriteOnPhone>());
    });
  });

  test('the chat template matches the one Ask has always sent', () {
    const prompt = WritingPrompt(system: 'S', user: 'U');
    expect(
      prompt.chatTemplate,
      '<|im_start|>system\nS<|im_end|>\n'
      '<|im_start|>user\nU<|im_end|>\n'
      '<|im_start|>assistant\n',
    );
    final now = DateTime(2026, 11, 8);
    expect(
      WritingPrompt(
        system: getAskAiSystemInstruction('A', now: now),
        user: buildAskAiUserMessage('q', 'c'),
      ).chatTemplate,
      buildAskAiQwenPrompt('q', 'c', 'A', now: now),
    );
  });

  group('ReplyDrafter.draft', () {
    final request = ReplyRequest(_message(), null);
    final withGist = ReplyRequest(_message(), "i'll be there");

    Future<WritingRoute> Function(SharedPreferences) to(WritingRoute r) =>
        (_) async => r;

    DraftWriter writes(
      Stream<String> Function() make, {
      void Function(WritingRoute, WritingPrompt, int)? seen,
    }) =>
        (route, prompt, {required maxTokens, required temperature, cancel}) {
          seen?.call(route, prompt, maxTokens);
          return make();
        };

    test('On this phone writes a draft with no gist', () async {
      WritingRoute? used;
      WritingPrompt? asked;
      int? tokens;
      final text = await ReplyDrafter.draft(
        request,
        route: to(const WriteOnPhone('m')),
        write: writes(
          () => Stream.fromIterable(['Yes, ', "I'm in!<|im_end|>"]),
          seen: (r, p, t) {
            used = r;
            asked = p;
            tokens = t;
          },
        ),
      );
      expect(text, "Yes, I'm in!");
      expect(used, isA<WriteOnPhone>());
      expect(asked!.system, startsWith(draftInstruction));
      expect(asked!.chatTemplate, contains('Coorg on Friday?'));
      expect(tokens, lessThanOrEqualTo(100));
    });

    test('the computer route writes too', () async {
      final text = await ReplyDrafter.draft(
        request,
        route: to(const WriteOnComputer('h:1')),
        write: writes(() => Stream.value('On my way')),
      );
      expect(text, 'On my way');
    });

    test('no engine keeps the owner\'s words, or an empty draft', () async {
      var called = false;
      final write = writes(() {
        called = true;
        return const Stream.empty();
      });
      expect(
        await ReplyDrafter.draft(
          request,
          route: to(const NoWritingRoute()),
          write: write,
        ),
        '',
      );
      expect(
        await ReplyDrafter.draft(
          withGist,
          route: to(const NoWritingRoute()),
          write: write,
        ),
        "I'll be there",
      );
      expect(called, isFalse);
    });

    test('a failing engine falls back', () async {
      expect(
        await ReplyDrafter.draft(
          withGist,
          route: to(const WriteWithGemini('k')),
          write: writes(() => Stream.error(Exception('down'))),
        ),
        "I'll be there",
      );
    });

    test('a blank first inference on the phone is retried once', () async {
      var calls = 0;
      final text = await ReplyDrafter.draft(
        request,
        route: to(const WriteOnPhone('m')),
        write: writes(() {
          calls++;
          return calls == 1 ? const Stream.empty() : Stream.value('Sure');
        }),
      );
      expect(text, 'Sure');
      expect(calls, 2);
    });

    test('a blank answer elsewhere is not retried', () async {
      var calls = 0;
      await ReplyDrafter.draft(
        request,
        route: to(const WriteWithGemini('k')),
        write: writes(() {
          calls++;
          return const Stream.empty();
        }),
      );
      expect(calls, 1);
    });

    test('recited instructions are not offered as a draft', () async {
      expect(
        await ReplyDrafter.draft(
          withGist,
          route: to(const WriteWithGemini('k')),
          write: writes(
            () => Stream.value('Write a short chat message for the user.'),
          ),
        ),
        "I'll be there",
      );
    });

    test('running out of patience stops the engine and falls back', () async {
      var cancelled = false;
      final endless = StreamController<String>(
        onCancel: () => cancelled = true,
      );
      final text = await ReplyDrafter.draft(
        withGist,
        route: to(const WriteOnPhone('m')),
        write: writes(() => endless.stream),
        patience: const Duration(milliseconds: 20),
      );
      expect(text, "I'll be there");
      expect(cancelled, isTrue);
    });
  });

  group('clampDraft', () {
    test('keeps only the first paragraph', () {
      expect(clampDraft('Sure.\n\nAlso this other thing.'), 'Sure.');
    });

    test('a long draft ends at a sentence', () {
      final first = 'I can make it on Friday if we leave early enough.';
      final text = clampDraft('$first ${'word ' * 80}');
      expect(text, first);
    });

    test('a long sentence ends at a word', () {
      final text = clampDraft('word ' * 80);
      expect(text.length, lessThanOrEqualTo(maxDraftChars));
      expect(text.endsWith('word'), isTrue);
    });

    test('never splits an emoji', () {
      final text = clampDraft('${'a' * (maxDraftChars - 1)}😀 more');
      expect(text.endsWith('\uD83D'), isFalse);
    });
  });

  group('OnPhoneWriter', () {
    final callbacks = <FllamaInferenceCallback>[];
    final cancelled = <int>[];
    final saveStart = OnPhoneWriter.startInference;
    final saveCancel = OnPhoneWriter.cancelInference;

    setUp(() {
      callbacks.clear();
      cancelled.clear();
      OnPhoneWriter.startInference = (request, callback) async {
        callbacks.add(callback);
        return callbacks.length;
      };
      OnPhoneWriter.cancelInference = cancelled.add;
    });

    tearDown(() {
      OnPhoneWriter.startInference = saveStart;
      OnPhoneWriter.cancelInference = saveCancel;
    });

    FllamaInferenceRequest request() => FllamaInferenceRequest(
      contextSize: 16384,
      input: 'x',
      maxTokens: 10,
      modelPath: 'm',
      numGpuLayers: 0,
      temperature: 0.3,
      penaltyFrequency: 0,
      penaltyRepeat: 1.1,
      topP: 0.9,
    );

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('turns cumulative text into pieces', () async {
      final pieces = <String>[];
      final done = OnPhoneWriter.run(request()).listen(pieces.add).asFuture();
      await settle();
      callbacks[0]('He', '', false);
      callbacks[0]('Hello', '', true);
      await done;
      expect(pieces, ['He', 'llo']);
    });

    test('a draft waits for an Ask answer to finish', () async {
      OnPhoneWriter.run(request()).listen((_) {});
      OnPhoneWriter.run(request()).listen((_) {});
      await settle();
      expect(callbacks, hasLength(1));
      callbacks[0]('done', '', true);
      await settle();
      expect(callbacks, hasLength(2));
      callbacks[1]('done', '', true);
      await settle();
    });

    test('leaving cancels the inference and frees the model', () async {
      final sub = OnPhoneWriter.run(request()).listen((_) {});
      OnPhoneWriter.run(request()).listen((_) {});
      await settle();
      await sub.cancel();
      expect(cancelled, [1]);
      await settle();
      expect(callbacks, hasLength(2));
      callbacks[1]('done', '', true);
      await settle();
    });

    test('a cancelled request still waiting never starts', () async {
      final cancel = WritingCancel();
      OnPhoneWriter.run(request()).listen((_) {});
      OnPhoneWriter.run(request(), cancel: cancel).listen((_) {});
      await settle();
      cancel.cancel();
      callbacks[0]('done', '', true);
      await settle();
      expect(callbacks, hasLength(1));
    });
  });
}
