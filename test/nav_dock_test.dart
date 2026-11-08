import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/core/presentation/widgets/nav_dock.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.lightTheme,
  home: Scaffold(body: Center(child: child)),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the dock fits a 320 dp phone', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _host(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: NavDock(
            selectedIndex: 1,
            onTabSelected: (_) {},
            asking: false,
            onOpenAsk: () {},
            onCloseAsk: () {},
            onAsk: (_) {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
