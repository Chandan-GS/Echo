import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/features/desktop/presentation/ask/desktop_ask_screen.dart';
import 'package:project_echo/features/desktop/presentation/ask/sources_pane.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/presentation/cubit/ask_ai_cubit.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/answer_view.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/ask_parts.dart';
import 'package:shared_preferences/shared_preferences.dart';

RawData note(String sender, String content) => RawData()
  ..source = 'Slack'
  ..sender = sender
  ..content = content
  ..timestamp = DateTime(2026, 9, 26, 11, 2);

void main() {
  final neha = note('Neha', 'Deck by noon?');
  final priya = note('Priya', 'Pricing slide?');
  final arjun = note('Arjun', 'HDMI adapter?');
  final answer = ChatMessage(
    sender: 'echo',
    text:
        'Neha needs the deck by **noon** [1], and Arjun wants the adapter [3].',
    ragSources: [neha, priya, arjun],
  );

  Widget app(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('an answer', () {
    testWidgets('on the phone keeps its source cards and opens a source', (
      tester,
    ) async {
      RawData? opened;
      await tester.pumpWidget(
        app(AnswerView(message: answer, onOpenSource: (e) => opened = e)),
      );
      expect(find.text(arjun.content), findsOneWidget);
      await tester.tap(find.widgetWithText(CiteDot, '3').first);
      expect(opened, arjun);
    });

    testWidgets('beside a sources pane reports hovers and clicks instead', (
      tester,
    ) async {
      final cited = <int>[];
      RawData? opened;
      await tester.pumpWidget(
        app(
          AnswerView(
            message: answer,
            onOpenSource: (e) => opened = e,
            onCite: cited.add,
          ),
        ),
      );
      expect(find.text(arjun.content), findsNothing);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.widgetWithText(CiteDot, '1')));
      await tester.pump();
      await tester.tap(find.widgetWithText(CiteDot, '3'));
      expect(cited, [1, 3]);
      expect(opened, isNull);
    });
  });

  group('the sources pane', () {
    testWidgets('lists what the answer cites, in full', (tester) async {
      int? picked;
      RawData? reply;
      RawData? open;
      await tester.pumpWidget(
        app(
          SourcesPane(
            answer: answer,
            question: 'What do I need before the demo?',
            onPick: (n) => picked = n,
            onReply: (e) => reply = e,
            onOpen: (e) => open = e,
          ),
        ),
      );
      expect(find.text(neha.content), findsOneWidget);
      expect(find.text(arjun.content), findsOneWidget);
      expect(find.text(priya.content), findsNothing);
      expect(
        find.text('For “What do I need before the demo?”'),
        findsOneWidget,
      );

      await tester.tap(find.text(arjun.content));
      expect(picked, 3);
      await tester.tap(find.text('Reply').first);
      expect(reply, neha);
      await tester.tap(find.text('Open').last);
      expect(open, arjun);
    });

    testWidgets('is calm before there is an answer', (tester) async {
      await tester.pumpWidget(
        app(
          SourcesPane(
            answer: null,
            onPick: (_) {},
            onReply: (_) {},
            onOpen: (_) {},
          ),
        ),
      );
      expect(find.text('Sources show here when Echo answers.'), findsOneWidget);
    });

    test('says when a message came in', () {
      final now = DateTime(2026, 9, 26, 18);
      expect(sentLabel(DateTime(2026, 9, 26, 11, 2), now), '11:02 AM');
      expect(
        sentLabel(DateTime(2026, 9, 25, 21, 40), now),
        'Yesterday 9:40 PM',
      );
      expect(sentLabel(DateTime(2026, 9, 21, 9), now), 'Mon 9:00 AM');
      expect(sentLabel(DateTime(2026, 9, 12, 9), now), '12 Sep');
    });
  });

  testWidgets('the screen opens on its header and an empty pane', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(const DesktopAskScreen()));
    await tester.pump();
    expect(find.text('Ask Echo'), findsOneWidget);
    expect(find.text('New question'), findsOneWidget);
    expect(find.text('Sources show here when Echo answers.'), findsOneWidget);
  });
}
