import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/features/todo/presentation/screens/todo_celebration_screen.dart';

void main() {
  testWidgets('the celebration fits a small phone at the largest text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 1280); // 360 × 640 dp
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(360, 640),
            textScaler: TextScaler.linear(2),
          ),
          child: TodoCelebrationScreen(done: 12, tomorrow: 4),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 3));

    expect(tester.takeException(), isNull);
    // Still reachable, by scrolling.
    await tester.scrollUntilVisible(find.text('Nice'), 200);
    expect(find.text('Nice'), findsOneWidget);
  });
}
