import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_mascot.dart';
import 'package:project_echo/features/onboarding/presentation/screens/welcome_screen.dart';

void main() {
  testWidgets('Echo wakes up, then says hello', (tester) async {
    tester.view.physicalSize = const Size(1080, 2392);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: WelcomeScreen()));
    await tester.pump();

    EchoState stateNow() =>
        tester.widget<EchoMascot>(find.byType(EchoMascot)).state;
    double opacityOf(String text) => tester
        .widget<Opacity>(
          find
              .ancestor(of: find.text(text), matching: find.byType(Opacity))
              .first,
        )
        .opacity;

    // The storyboard plays at two-thirds speed: 4.5 seconds in all.
    // Asleep, with the words still hidden.
    await tester.pump(const Duration(milliseconds: 600));
    expect(stateNow(), EchoState.sleeping);
    expect(opacityOf('Echo'), 0);

    // Awake, then happy.
    await tester.pump(const Duration(milliseconds: 1500));
    expect(stateNow(), EchoState.idle);
    await tester.pump(const Duration(milliseconds: 600));
    expect(stateNow(), EchoState.happy);

    // Risen, and saying hello.
    await tester.pump(const Duration(milliseconds: 1950));
    expect(stateNow(), EchoState.idle);
    expect(opacityOf('Echo'), 1);
    expect(find.text('Get Started'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
