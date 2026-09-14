import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_echo/main.dart';

void main() {
  testWidgets('Echo boots to the home screen without crashing',
      (WidgetTester tester) async {
    // Use a desktop-sized viewport. On a macOS/Windows test host the app
    // renders the desktop three-pane shell (Platform.isMacOS/isWindows is
    // true), which needs real width; a wide surface is also fine for the
    // phone layout on other hosts. The default 800x600 is too cramped for the
    // sidebar + right rail and overflows.
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(Echo(isOnboardingFinished: true));
    // NextBriefingTimer runs an infinite (repeating) animation, so
    // pumpAndSettle would time out — pump a couple of discrete frames instead.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // The app renders and reaches the home screen greeting ("Good morning/…").
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.textContaining('Good'), findsWidgets);
  });
}
