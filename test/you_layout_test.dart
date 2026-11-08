import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/features/profile/data/week_stats.dart';
import 'package:project_echo/features/profile/presentation/screens/profile_screen.dart';
import 'package:project_echo/features/profile/presentation/widgets/share_week_sheet.dart';

void main() {
  final week = WeekStats(
    todosDone: 9,
    todosDue: 10,
    replies: 4,
    readByDay: const [412, 380, 498, 521, 476, 503, 424],
    from: DateTime(2026, 11, 2),
    peopleAnswered: 23,
    answeredByDay: const [3, 2, 5, 4, 3, 4, 2],
    held: 146,
  );

  Future<void> pumpAt(
    WidgetTester tester,
    Widget child, {
    required double width,
    required double scale,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = Size(width * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.lightTheme,
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 800),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 900));
  }

  for (final (width, scale) in const [
    (320.0, 1.0),
    (320.0, 1.6),
    (412.0, 2.0),
  ]) {
    testWidgets('week chart fits at ${width}dp, text x$scale', (tester) async {
      await pumpAt(
        tester,
        WeekBarChart(
          title: 'People you got back to',
          byDay: week.answeredByDay,
          from: week.from,
        ),
        width: width,
        scale: scale,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('share sheet opens narrow, in dark, with numbers on the card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320 * 3, 720 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showShareWeekSheet(
                context,
                week: week,
                streak: 4,
                range: '2 Nov – 8 Nov',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(find.text('23'), findsOneWidget);
    expect(find.text('9/10'), findsOneWidget);
    expect(find.text('4 days'), findsOneWidget);
  });
}
