import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/features/echo/data/ask/conversation_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';

DateTime at(int day, int hour, [int minute = 0]) =>
    DateTime(2026, 9, day, hour, minute);

ConversationTurn turn(String q, DateTime when, {List<double>? e}) =>
    ConversationTurn(
      question: q,
      answer: 'Kavya has a movie on Sunday at 6:30 PM.',
      sourceIds: const [7],
      embedding: e,
      at: when,
    );

List<double> unit(int dims, int hot) =>
    List<double>.generate(dims, (i) => i == hot ? 1.0 : 0.0);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('persists across loads on the same day and resets the next day',
      () async {
    final memory = await ConversationMemory.load(at(26, 10));
    await memory.add(turn('Any plans for Sunday?', at(26, 10)));

    expect((await ConversationMemory.load(at(26, 18))).turns, hasLength(1));
    expect((await ConversationMemory.load(at(27, 7))).turns, isEmpty);
  });

  test('keeps only the last few turns', () async {
    final memory = await ConversationMemory.load(at(26, 10));
    for (var i = 0; i < 6; i++) {
      await memory.add(turn('q$i', at(26, 10, i)));
    }
    final reloaded = await ConversationMemory.load(at(26, 11));
    expect(reloaded.turns.map((t) => t.question),
        ['q2', 'q3', 'q4', 'q5']);
  });

  group('follow-up detection', () {
    late ConversationMemory memory;
    setUp(() async {
      memory = await ConversationMemory.load(at(26, 10));
      await memory.add(turn('Any plans for Sunday?', at(26, 10), e: unit(4, 0)));
    });

    test('pronouns, connectives and very short questions are follow-ups', () {
      expect(memory.isFollowUp('What time is it?', null, at(26, 10, 5)), isTrue);
      expect(memory.isFollowUp('and Neha?', null, at(26, 10, 5)), isTrue);
      expect(memory.isFollowUp('did she confirm', null, at(26, 10, 5)), isTrue);
    });

    test('a new, unrelated question is not', () {
      expect(
        memory.isFollowUp('What did the bank send about my card statement',
            unit(4, 1), at(26, 10, 5)),
        isFalse,
      );
    });

    test('a similar question (by MiniLM embedding) is', () {
      expect(
        memory.isFollowUp('Remind me of the Sunday plans with the movie',
            unit(4, 0), at(26, 10, 5)),
        isTrue,
      );
    });

    test('nothing counts as a follow-up hours later', () {
      expect(memory.isFollowUp('and Neha?', null, at(26, 14)), isFalse);
    });
  });

  test('history is compact: last two exchanges, long answers clipped',
      () async {
    final memory = await ConversationMemory.load(at(26, 10));
    await memory.add(turn('first', at(26, 10)));
    await memory.add(ConversationTurn(
      question: 'second',
      answer: 'x' * 500,
      sourceIds: const [],
      embedding: null,
      at: at(26, 10, 1),
    ));
    await memory.add(turn('third', at(26, 10, 2)));

    final history = memory.historyForPrompt();
    expect(history, isNot(contains('first')));
    expect(history, contains('User: second'));
    expect(history, contains('User: third'));
    expect(history.length, lessThan(400));
  });

  test('blended embeddings lean towards the previous question, unit length',
      () {
    final blended = blendEmbeddings(unit(4, 0), unit(4, 1))!;
    final norm = math.sqrt(blended.fold<double>(0, (s, v) => s + v * v));
    expect(norm, closeTo(1, 1e-9));
    expect(blended[0], greaterThan(blended[1]));
    expect(blended[1], greaterThan(0));
  });
}
