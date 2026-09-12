import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_echo/main.dart';

void main() {
  testWidgets('Echo boots to the home screen without crashing',
      (WidgetTester tester) async {
    // Use a realistic phone-portrait viewport. The default 800x600 test surface
    // is wide-and-short, which clips the full-height home layout.
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
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
