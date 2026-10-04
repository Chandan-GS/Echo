import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/features/desktop/presentation/typing.dart';

void main() {
  testWidgets('a text field is typing; selectable message text is not', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TextField(key: Key('field')),
              SelectableText('Can you send me the deck?', key: Key('message')),
            ],
          ),
        ),
      ),
    );
    expect(typingInAField(), isFalse);

    // Clicking a message to copy from it focuses its read-only text.
    await tester.tap(find.byKey(const Key('message')));
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.context, isNotNull);
    expect(typingInAField(), isFalse);

    await tester.tap(find.byKey(const Key('field')));
    await tester.pump();
    expect(typingInAField(), isTrue);
  });
}
