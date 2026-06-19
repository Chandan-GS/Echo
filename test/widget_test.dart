import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/main.dart';

void main() {
  testWidgets('Echo smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const Echo());

    // Basic assertion that the welcome text/button exists.
    expect(find.text('Echo'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
  });
}
