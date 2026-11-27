import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/core/presentation/animations/fade_indexed_stack.dart';
import 'package:project_echo/core/presentation/widgets/animated_nav_icons.dart';
import 'package:project_echo/core/presentation/widgets/echo_segmented.dart';
import 'package:project_echo/core/presentation/widgets/min_tap_area.dart';
import 'package:project_echo/core/presentation/widgets/nav_dock.dart';
import 'package:project_echo/core/presentation/animations/fade_slide_in.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_mascot.dart';
import 'package:project_echo/features/echo/presentation/widgets/home_sections.dart';
import 'package:project_echo/features/profile/data/week_stats.dart';
import 'package:project_echo/features/profile/presentation/screens/profile_screen.dart';
import 'package:project_echo/features/vault/presentation/widgets/category_pie_chart.dart';

/// Counts how often it's created, and remembers whether its tickers run.
class _Probe extends StatefulWidget {
  final String name;
  const _Probe(this.name);

  static final inits = <String, int>{};
  static final ticking = <String, bool>{};

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  final _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    _Probe.inits.update(widget.name, (n) => n + 1, ifAbsent: () => 1);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _Probe.ticking[widget.name] = TickerMode.valuesOf(context).enabled;
    return Material(
      child: TextField(
        key: ValueKey('field-${widget.name}'),
        controller: _text,
      ),
    );
  }
}

Widget _app(
  Widget child, {
  double width = 412,
  double textScale = 1,
  bool disableAnimations = false,
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          size: Size(width, 800),
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: Scaffold(
          body: Center(
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('FadeIndexedStack', () {
    setUp(() {
      _Probe.inits.clear();
      _Probe.ticking.clear();
    });

    Widget stack(int index, {bool still = false}) => _app(
      SizedBox(
        height: 400,
        child: FadeIndexedStack(
          index: index,
          children: const [_Probe('a'), _Probe('b')],
        ),
      ),
      disableAnimations: still,
    );

    testWidgets('switching tabs keeps their state', (tester) async {
      await tester.pumpWidget(stack(0));
      await tester.enterText(
        find.byKey(const ValueKey('field-a')),
        'half typed',
      );

      for (final i in [1, 0, 1, 0]) {
        await tester.pumpWidget(stack(i));
        await tester.pump(const Duration(milliseconds: 500));
      }

      // Each tab was built once, and what was typed is still there.
      expect(_Probe.inits, {'a': 1, 'b': 1});
      expect(find.text('half typed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hidden tabs have their tickers muted', (tester) async {
      await tester.pumpWidget(stack(0));
      expect(_Probe.ticking, {'a': true, 'b': false});

      await tester.pumpWidget(stack(1));
      await tester.pump(const Duration(milliseconds: 500));
      expect(_Probe.ticking, {'a': false, 'b': true});
    });

    testWidgets('with animations off, the new tab is there at once', (
      tester,
    ) async {
      await tester.pumpWidget(stack(0, still: true));
      await tester.pumpWidget(stack(1, still: true));
      await tester.pump();
      final opacity = tester.widget<Opacity>(
        find
            .ancestor(
              of: find.byType(_Probe).last,
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(opacity.opacity, 1);
    });
  });

  group('NavDock', () {
    Widget dock({
      required double screen,
      double textScale = 1,
      bool asking = false,
      ValueChanged<int>? onTab,
    }) => _app(
      // Placed as the scaffold places it: 20 dp in from each side.
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: NavDock(
          selectedIndex: 0,
          onTabSelected: onTab ?? (_) {},
          asking: asking,
          onOpenAsk: () {},
          onCloseAsk: () {},
          onAsk: (_) {},
        ),
      ),
      width: screen,
      textScale: textScale,
    );

    for (final (screen, scale) in [
      (320.0, 1.0),
      (280.0, 1.0),
      (412.0, 2.0),
      (320.0, 2.0),
    ]) {
      testWidgets('lays out at $screen dp, ${scale}x text', (tester) async {
        await tester.pumpWidget(dock(screen: screen, textScale: scale));
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
        expect(find.byType(ErrorWidget), findsNothing);

        // Folding into the question bar and back.
        await tester.pumpWidget(
          dock(screen: screen, textScale: scale, asking: true),
        );
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(dock(screen: screen, textScale: scale));
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('keeps its look on an ordinary phone', (tester) async {
      await tester.pumpWidget(dock(screen: 412));
      await tester.pump(const Duration(milliseconds: 500));
      // Four 66 dp tabs and the 6 dp inset either side.
      final pill = tester.getSize(find.byType(NavDock));
      expect(pill.height, kNavDockHeight);
      final home = tester.getSize(
        find
            .ancestor(
              of: find.byType(SquashInIcon).first,
              matching: find.byType(GestureDetector),
            )
            .first,
      );
      // The dock's full height inside its hairline border.
      expect(home, const Size(66, kNavDockHeight - 2));
    });

    testWidgets('a tab takes a tap at the very edge of the dock', (
      tester,
    ) async {
      int? tapped;
      await tester.pumpWidget(dock(screen: 412, onTab: (i) => tapped = i));
      await tester.pump(const Duration(milliseconds: 500));
      final todo = find.bySemanticsLabel('To-do');
      final rect = tester.getRect(todo);
      expect(rect.height, greaterThanOrEqualTo(kMinTapTarget));
      // 2 dp below the dock's top edge, outside the green pill's inset.
      final dockTop = tester.getRect(find.byType(NavDock)).top;
      await tester.tapAt(Offset(rect.center.dx, dockTop + 2));
      expect(tapped, 1);
    });
  });

  group('Large text', () {
    testWidgets('Ask chips grow with the font and keep 40 dp at 1x', (
      tester,
    ) async {
      Future<double> rowHeight(double scale) async {
        await tester.pumpWidget(
          _app(
            AskSuggestionChips(questions: kAskSuggestions, onAsk: (_) {}),
            textScale: scale,
          ),
        );
        expect(tester.takeException(), isNull);
        return tester.getSize(find.byType(AskSuggestionChips)).height;
      }

      expect(await rowHeight(1), 40);
      expect(await rowHeight(2), greaterThan(40));
    });

    testWidgets('section headers wrap instead of overflowing', (tester) async {
      await tester.pumpWidget(
        _app(
          HomeSectionHeader(
            'Up next',
            action: 'All 12 in To-do',
            onAction: () {},
          ),
          width: 280,
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets("the profile's week tiles and chart don't clip", (
      tester,
    ) async {
      final now = DateTime(2026, 11, 26);
      final week = WeekStats(
        todosDone: 12,
        replies: 4,
        readByDay: const [3, 9, 1, 0, 14, 7, 5],
        from: now.subtract(const Duration(days: 6)),
      );
      await tester.pumpWidget(
        _app(
          SingleChildScrollView(child: WeekInNumbers(week: week)),
          width: 320,
          textScale: 2,
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      final e = tester.takeException();
      if (e != null) debugPrint((e as FlutterError).toStringDeep());
      expect(e, isNull);
    });
  });

  group('Tap targets', () {
    testWidgets('MinTapArea takes taps near a small control', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _app(
          SizedBox(
            height: 200,
            child: Center(
              child: MinTapArea(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps++,
                  child: const SizedBox.square(dimension: 20),
                ),
              ),
            ),
          ),
          width: 200,
        ),
      );
      final dot = tester.getRect(find.byType(MinTapArea));
      expect(dot.size, const Size.square(20)); // Its own size is unchanged.

      await tester.tapAt(dot.center + const Offset(13, 0)); // 3 dp outside
      await tester.tapAt(dot.center + const Offset(0, -23)); // 13 dp above
      expect(taps, 2);

      await tester.tapAt(dot.center + const Offset(30, 0)); // too far
      expect(taps, 2);
    });
  });

  group('Reduce motion', () {
    testWidgets('Echo holds still and entrances are skipped', (tester) async {
      await tester.pumpWidget(
        _app(
          const FadeSlideIn(
            delay: Duration(milliseconds: 300),
            child: EchoMascot(size: 80),
          ),
          disableAnimations: true,
        ),
      );
      await tester.pump();
      // No looping animation asks for frames, and the child is shown.
      expect(tester.binding.hasScheduledFrame, isFalse);
      final fade = tester.widget<Opacity>(
        find
            .ancestor(
              of: find.byType(EchoMascot),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(fade.opacity, 1);
    });
  });

  group('Semantics', () {
    testWidgets('EchoSegmented says which choice is selected', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          EchoSegmented(
            labels: const ['System', 'Light', 'Dark'],
            selected: 1,
            onSelect: (_) {},
          ),
        ),
      );
      expect(
        tester.getSemantics(find.text('Light')),
        matchesSemantics(
          label: 'Light',
          isButton: true,
          isSelected: true,
          isInMutuallyExclusiveGroup: true,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.text('Dark')),
        matchesSemantics(
          label: 'Dark',
          isButton: true,
          isInMutuallyExclusiveGroup: true,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('each pie slice is a button TalkBack can open', (tester) async {
      final handle = tester.ensureSemantics();
      String? opened;
      await tester.pumpWidget(
        _app(
          SizedBox(
            height: 360,
            child: CategoryPieChart(
              categoryCounts: const {'Work': 3, 'Family': 1},
              onCategorySelected: (c) => opened = c,
            ),
          ),
        ),
      );
      final work = find.bySemanticsLabel('Work, 3 signals');
      expect(work, findsOneWidget);
      expect(find.bySemanticsLabel('Family, 1 signal'), findsOneWidget);

      final node = tester.getSemantics(work);
      node.owner!.performAction(node.id, SemanticsAction.tap);
      expect(opened, 'Work');
      handle.dispose();
    });
  });
}
