import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/presentation/screens/streak_celebration_screen.dart';
import 'package:project_echo/features/profile/data/week_card.dart';
import 'package:project_echo/features/profile/data/week_stats.dart';
import 'package:project_echo/features/profile/presentation/week_card_share.dart';
import 'package:project_echo/features/profile/presentation/widgets/week_card.dart';
import 'package:project_echo/features/todo/data/todo_item.dart';
import 'package:project_echo/features/vault/data/daily_stats.dart';

// Thu 26 Nov 2026, 8:30 PM.
final now = DateTime(2026, 11, 26, 20, 30);

WeekStats week({
  List<int> readByDay = const [50, 60, 70, 40, 80, 62, 50],
  int replies = 0,
}) => WeekStats.summarise(
  items: const [],
  replies: [for (var i = 0; i < replies; i++) DateTime(2026, 11, 25, 9, i)],
  readByDay: readByDay,
  now: now,
);

WeekCardData card({
  int read = 412,
  int mornings = 5,
  int replies = 12,
  int streak = 0,
}) => WeekCardData(
  read: read,
  mornings: mornings,
  replies: replies,
  streak: streak,
  from: DateTime(2026, 11, 20),
  to: DateTime(2026, 11, 26),
);

RawData msg(String app, String who, String text, String thread, int day) =>
    RawData()
      ..source = app
      ..sender = who
      ..content = text
      ..timestamp = DateTime(2026, 11, day, 9, 15)
      ..thread = thread
      ..addressed = 'direct';

/// Every string a Text or RichText in the tree draws.
List<String> drawnText(WidgetTester tester) => [
  for (final t in tester.widgetList<RichText>(find.byType(RichText)))
    t.text.toPlainText(),
];

void main() {
  group('putting the card together', () {
    test('counts the mornings heard in the last seven days only', () {
      final data = WeekCardData.assemble(
        week: week(replies: 12),
        heardDates: {
          '2026-11-12', // weeks ago
          '2026-11-19', // the day before the week
          '2026-11-20', // its first day
          '2026-11-22',
          '2026-11-23',
          '2026-11-25',
          '2026-11-26', // today
        },
        streak: 2,
        now: now,
      );
      expect(data.read, 412);
      expect(data.mornings, 5);
      expect(data.replies, 12);
      expect(data.streak, 2);
      expect(data.from, DateTime(2026, 11, 20));
      expect(data.to, DateTime(2026, 11, 26));
      expect(data.range, '20 – 26 Nov');
    });

    test('says it the way a person would', () {
      final data = card(read: 1284, streak: 6);
      expect(data.headline, 'This week Echo read 1,284 messages for me');
      expect(data.stats, [
        ('5 of 7', 'mornings I heard my briefing'),
        ('12', 'replies through Echo'),
        ('6 days', 'in a row with Echo'),
      ]);
      expect(
        data.shareText,
        'This week Echo read 1,284 messages for me · I heard 5 of 7 mornings'
        ' · 12 replies through Echo. Echo: AI Notification Summary, on Google'
        ' Play: ${WeekCardData.playLink}',
      );
      expect(WeekCardData.playLink, contains('utm_source%3Dshare_card'));
    });

    test('leaves out what is zero, and leads with mornings if nothing was '
        'read', () {
      final data = card(read: 0, mornings: 3, replies: 0, streak: 1);
      expect(data.headline, 'This week I heard 3 of 7 mornings');
      expect(data.stats, isEmpty);
      expect(card(replies: 1).stats[1], ('1', 'reply through Echo'));
      expect(card(read: 1).headline, contains('1 message for me'));
    });
  });

  group('when the share is offered', () {
    test('Profile offers it after a heard morning or a real number read', () {
      expect(card(read: 0, mornings: 1).worthSharing, isTrue);
      expect(card(read: 20, mornings: 0).worthSharing, isTrue);
      expect(card(read: 19, mornings: 0).worthSharing, isFalse);
      expect(card(read: 0, mornings: 0, replies: 4).worthSharing, isFalse);
    });

    for (final days in [1, 2, 3, 5, 7, 14, 21, 30, 31]) {
      final shown = {3, 7, 14, 30}.contains(days);
      testWidgets('the celebration ${shown ? 'offers' : 'does not offer'} '
          'it at $days days', (tester) async {
        await tester.pumpWidget(
          MaterialApp(home: StreakCelebrationScreen(days: days)),
        );
        await tester.pump(const Duration(seconds: 2));
        expect(find.text('Share'), shown ? findsOneWidget : findsNothing);
        expect(find.text('Continue'), findsOneWidget);
        if (shown) {
          final size = tester.getSize(find.byType(OutlinedButton));
          expect(size.height, greaterThanOrEqualTo(48));
          expect(size.width, greaterThanOrEqualTo(48));
          expect(
            tester.getSemantics(find.byType(OutlinedButton)),
            matchesSemantics(
              label: 'Share my week',
              isButton: true,
              hasTapAction: true,
              hasFocusAction: true,
              hasEnabledState: true,
              isEnabled: true,
              isFocusable: true,
            ),
          );
        }
      });
    }

    testWidgets('the Profile button is labelled and 48 dp tall', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(body: ShareWeekButton(onPressed: () {})),
        ),
      );
      final button = find.byType(TextButton);
      expect(find.text('Share my week'), findsOneWidget);
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      expect(tester.getSemantics(button).label, contains('Share my week'));
    });
  });

  group('privacy', () {
    // Notifications as they arrive: people, what they said, where.
    final fixtures = [
      msg(
        'WhatsApp',
        'Priya Sharma',
        'Dinner at 8? Bring the keys',
        'Family',
        24,
      ),
      msg(
        'Slack',
        'Rahul Verma',
        'Q3 deck needs the revenue slide',
        '#launch',
        25,
      ),
      msg('Gmail', 'HDFC Bank', 'Your OTP is 482913', 'Account alerts', 26),
      msg('Instagram', 'ananya.k', 'sent you a reel', 'ananya.k', 26),
    ];
    final secrets = {
      for (final n in fixtures) ...[n.source, n.sender, n.content, n.thread],
    }.whereType<String>().toList();

    WeekCardData fromFixtures() {
      var store = <String, dynamic>{};
      for (final n in fixtures) {
        store = DailyStats.added(store, n.source, n.timestamp, now);
      }
      // A to-do Echo made from one of them, carrying its sender and text.
      final todo = TodoItem(
        id: 1,
        title: fixtures[0].content,
        day: DateTime(2026, 11, 24),
        time: null,
        sort: 0,
        sender: fixtures[0].sender,
        app: fixtures[0].source,
        sourceText: fixtures[0].content,
        sourceKey: 'k1',
        created: now,
        done: true,
        doneAt: DateTime(2026, 11, 24, 10),
      );
      final stats = WeekStats.summarise(
        items: [todo],
        replies: [DateTime(2026, 11, 25, 9)],
        readByDay: [for (final d in DailyStats.weekFrom(store, now)) d.total],
        now: now,
      );
      return WeekCardData.assemble(
        week: stats,
        heardDates: {'2026-11-24', '2026-11-25', '2026-11-26'},
        streak: 3,
        now: now,
      );
    }

    test('the card is counts only: nothing from the notifications', () {
      final data = fromFixtures();
      expect(data.read, 4);
      expect(data.mornings, 3);
      for (final line in data.allText) {
        for (final s in secrets) {
          expect(line.toLowerCase(), isNot(contains(s.toLowerCase())));
        }
      }
    });

    testWidgets('and so is what it draws', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: WeekCard(data: fromFixtures())),
        ),
      );
      final drawn = drawnText(tester);
      expect(drawn, contains(WeekCardData.appTitle));
      for (final line in drawn) {
        for (final s in secrets) {
          expect(line.toLowerCase(), isNot(contains(s.toLowerCase())));
        }
      }
    });
  });

  group('the card fits', () {
    for (final scale in [1.0, 2.0]) {
      for (final (name, data) in [
        ('a full week', card(read: 128450, replies: 1204, streak: 365)),
        ('a quiet week', card(read: 0, mornings: 1, replies: 0)),
      ]) {
        testWidgets('$name at ${scale}x text', (tester) async {
          await tester.pumpWidget(
            MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Center(child: WeekCard(data: data)),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          expect(tester.getSize(find.byType(WeekCard)), WeekCard.size);
          expect(find.text(data.headline), findsOneWidget);
        });
      }
    }
  });

  testWidgets('it draws to a 1080 × 1350 PNG without being on screen', (
    tester,
  ) async {
    final out = Platform.environment['WEEK_CARD_OUT'];
    final bytes = await tester.runAsync(() async {
      if (out != null) {
        // Real fonts, to look at the result.
        for (final (family, files) in [
          ('Nunito', ['assets/fonts/Nunito-VariableFont_wght.ttf']),
          (
            'OldStandardTT',
            [
              'assets/fonts/OldStandardTT-Regular.ttf',
              'assets/fonts/OldStandardTT-Bold.ttf',
            ],
          ),
        ]) {
          final loader = FontLoader(family);
          for (final f in files) {
            loader.addFont(
              File(f).readAsBytes().then((b) => ByteData.view(b.buffer)),
            );
          }
          await loader.load();
        }
      }
      return WeekCardShare.render(
        WeekCard(data: card(streak: 6)),
        WeekCard.size,
        tester.view,
      );
    });
    final codec = await tester.runAsync(() => ui.instantiateImageCodec(bytes!));
    final frame = await tester.runAsync(() => codec!.getNextFrame());
    expect(frame!.image.width, 1080);
    expect(frame.image.height, 1350);
    if (out != null) File(out).writeAsBytesSync(bytes!);
  });
}
