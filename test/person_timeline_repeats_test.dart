import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/features/echo/data/context/chat_context_store.dart';
import 'package:project_echo/features/people/data/person_detail.dart';

void main() {
  final at = DateTime(2026, 11, 8, 15);

  test('a reply carried back by the next notification counts once', () {
    final out = withoutRepeats([
      MyTurn(at, 'On my way'),
      MyTurn(at.add(const Duration(seconds: 20)), ' On my way '),
    ]);
    expect(out, hasLength(1));
    expect(out.single.at, at);
  });

  test('saying the same thing later is a new line', () {
    final out = withoutRepeats([
      MyTurn(at, 'ok'),
      MyTurn(at.add(const Duration(minutes: 10)), 'ok'),
    ]);
    expect(out, hasLength(2));
  });

  test('different lines stay, oldest first', () {
    final out = withoutRepeats([
      MyTurn(at.add(const Duration(seconds: 5)), 'two'),
      MyTurn(at, 'one'),
    ]);
    expect(out.map((t) => t.text), ['one', 'two']);
  });
}
