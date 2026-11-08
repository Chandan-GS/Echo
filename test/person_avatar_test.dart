import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/core/presentation/widgets/person_avatar.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.lightTheme,
  home: Scaffold(body: Center(child: child)),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<String> initialOf(WidgetTester tester, String name) async {
    await tester.pumpWidget(_host(PersonAvatar(name: name, size: 44)));
    return tester.widget<Text>(find.byType(Text)).data!;
  }

  testWidgets('initial is the first letter in any script', (tester) async {
    expect(await initialOf(tester, 'rohan'), 'R');
    expect(await initialOf(tester, '🔥 Rohan'), 'R');
    expect(await initialOf(tester, 'प्रिया'), 'प्रि');
    expect(await initialOf(tester, '🎉🎉'), '🎉');
    expect(await initialOf(tester, '   '), '?');
    expect(await initialOf(tester, '+91 98765'), '9');
  });

  Color? tintOf(WidgetTester tester) {
    final box = tester.widget<DecoratedBox>(find.byType(DecoratedBox).first);
    return (box.decoration as BoxDecoration).color;
  }

  testWidgets('a name keeps its tint, ignoring case and spaces', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const PersonAvatar(name: 'Amma', size: 44)));
    final first = tintOf(tester);
    await tester.pumpWidget(
      _host(const PersonAvatar(name: ' amma ', size: 44)),
    );
    expect(tintOf(tester), first);
  });

  testWidgets('a ring draws at every age, out of range included', (
    tester,
  ) async {
    for (final age in [-1, 0, 1, 2, 9]) {
      await tester.pumpWidget(
        _host(
          PersonAvatar(name: 'Amma', size: 44, ring: (age: age, progress: 1.4)),
        ),
      );
      expect(tester.takeException(), isNull);
    }
  });
}
