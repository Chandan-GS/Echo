import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/features/echo/data/waiting/wait_intent.dart';

void main() {
  final lines = File('test/fixtures/wait_intent_vectors.tsv')
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty && !l.startsWith('#'))
      .map((l) => l.split('\t'))
      .toList();

  group('shared vectors', () {
    for (final v in lines) {
      test('${v[0]}: ${v[4]}', () {
        final r = classifyWait(v[4], isGroup: v[2] == 'true', addressed: v[3]);
        expect(r.kind.name, v[0]);
        expect(r.needsReply, v[1] == 'true');
      });
    }

    test('the list covers every kind', () {
      expect(lines.map((v) => v[0]).toSet(), {
        for (final k in WaitKind.values) k.name,
      });
    });
  });

  group('WaitingIntent.kt keeps the same tables', () {
    final kotlin = File(
      'android/app/src/main/kotlin/com/chandangs/echo/WaitingIntent.kt',
    ).readAsStringSync();

    for (final MapEntry(key: name, value: table) in waitPhraseTables.entries) {
      test(name, () {
        final body = RegExp(
          'val $name = (?:listOf|setOf)\\(([\\s\\S]*?)\\n    \\)',
        ).firstMatch(kotlin);
        expect(body, isNotNull, reason: 'no table named $name');
        final phrases = RegExp(
          r'"([^"]*)"',
        ).allMatches(body!.group(1)!).map((m) => m.group(1)).toList();
        expect(phrases, table);
      });
    }
  });

  group('what Why? says', () {
    test('quotes the ask and the deadline', () {
      final r = classifyWait(
        'Call when free. Electricity bill is due tomorrow.',
        isGroup: false,
        addressed: 'direct',
      );
      expect(r.label, 'Asked you to call');
      expect(r.signals, [
        'A one-to-one chat',
        'Asks you to do something: “Call when free”',
        'Has a deadline: “due tomorrow”',
      ]);
    });

    test('quotes the question as it was written', () {
      final r = classifyWait(
        "Coorg on Friday? I'm driving, leaving early. You in?",
        isGroup: false,
        addressed: 'direct',
      );
      expect(r.signals.last, 'Ends with a question: “You in?”');
    });

    test('a mention is the headline', () {
      final r = classifyWait(
        'Can you sign off the release notes before 5?',
        isGroup: true,
        addressed: 'mentioned',
      );
      expect(r.label, 'Mentioned you with a request');
      expect(r.signals.first, 'A group message that mentions you');
      expect(r.signals.last, 'Has a deadline: “before 5”');
    });

    test('long messages are clipped, Hindi words survive', () {
      final r = classifyWait(
        'कल तक report भेज दो',
        isGroup: false,
        addressed: 'direct',
      );
      expect(r.kind, WaitKind.request);
      expect(r.signals.last, 'Has a deadline: “कल तक report भेज”');
      final long = classifyWait(
        'please ${'word ' * 60}',
        isGroup: false,
        addressed: 'direct',
      );
      expect(long.signals[1].length, lessThan(90));
    });
  });

  test('an empty message asks nothing', () {
    expect(
      classifyWait('   ', isGroup: false, addressed: 'direct').needsReply,
      isFalse,
    );
  });
}
