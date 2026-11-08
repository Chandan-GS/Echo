import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/people/data/group_page.dart';
import 'package:project_echo/features/people/data/group_rules.dart';
import 'package:project_echo/features/people/data/people_store.dart';
import 'package:project_echo/features/people/data/person_detail.dart';
import 'package:project_echo/features/people/data/person_loops.dart';
import 'package:project_echo/features/people/data/person_tally.dart';
import 'package:project_echo/features/people/presentation/screens/group_screen.dart';
import 'package:project_echo/features/people/presentation/screens/people_screen.dart';
import 'package:project_echo/features/people/presentation/screens/person_screen.dart';
import 'package:project_echo/features/todo/data/todo_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

const longName = 'Bhagyashree Venkataraghavan Krishnamurthy-Subramanian 🌸';
final now = DateTime(2026, 11, 8, 12);

OweLine owe(String t) => OweLine(
  title: t,
  meta: 'Asked yesterday · on your to-do list · quite a long meta line here',
  at: now,
  age: 2,
  todo: TodoItem(
    id: 1,
    title: t,
    day: now,
    time: null,
    sort: 0,
    sender: 'x',
    app: 'Whatsapp',
    sourceText: t,
    sourceKey: 'x|1',
    created: now,
  ),
);

PersonSummary summary({
  String name = longName,
  Drift? drift,
  PersonLoops loops = const PersonLoops([], []),
  BirthdayNote? birthday,
}) => PersonSummary(
  key: 'whatsapp|$name',
  name: name,
  source: 'Whatsapp',
  sources: const ['Whatsapp', 'Slack'],
  weekCount: 3,
  lastAt: now,
  drifting: drift != null,
  rhythm: 'Every day',
  drift: drift,
  loops: loops,
  birthday: birthday,
);

Future<void> pump(WidgetTester t, Widget child, {ThemeData? theme}) async {
  t.view.physicalSize = const Size(320, 700);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.lightTheme,
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 700),
          textScaler: TextScaler.linear(1.6),
        ),
        child: Scaffold(body: child),
      ),
    ),
  );
  await t.pump(const Duration(milliseconds: 100));
  await t.pump(const Duration(seconds: 1));
}

/// Scrolls to the bottom, so everything built lazily gets laid out too.
Future<void> scrollToEnd(WidgetTester t) async {
  final scrollable = find.byType(Scrollable).first;
  for (var i = 0; i < 40; i++) {
    final before = t.state<ScrollableState>(scrollable).position.pixels;
    await t.drag(scrollable, const Offset(0, -500));
    await t.pump(const Duration(milliseconds: 100));
    if (t.state<ScrollableState>(scrollable).position.pixels == before) break;
  }
  await t.pump(const Duration(seconds: 1));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final loops = PersonLoops(
    [owe('Pay the electricity bill before it gets cut off on Friday please')],
    [
      OwesLine(
        asked: 'Can you send me the wedding photos when you get a chance?',
        meta: 'Asked Tuesday · nothing since',
        askedAt: DateTime(2026, 11, 3, 12),
        thread: 't',
        followUpDue: true,
      ),
    ],
  );

  for (final (name, theme) in [
    ('light', AppTheme.lightTheme),
    ('dark', AppTheme.darkTheme),
  ]) {
    testWidgets('People tab fits a narrow phone, $name', (t) async {
      final feed = PeopleFeed(
        birthdays: [
          summary(
            birthday: const BirthdayNote(
              groups: ['College gang', 'Office'],
              wishers: ['Rohan', 'Riya', 'Priya'],
            ),
          ),
        ],
        drifting: [
          summary(
            drift: const Drift(
              line: 'Usually every day. No messages in 6 days.',
              bars: [12, 14, 11, 13, 12, 10, 3, 1],
              low: 2,
              silentDays: 6,
              progress: 0.5,
            ),
          ),
        ],
        loops: [summary(loops: loops)],
        everyone: [summary(), summary(name: 'नेहा')],
      );
      await pump(t, PeopleScreen(loader: (_) async => feed), theme: theme);
      expect(t.takeException(), isNull);
      // Below the fold at this size, and built only once scrolled near.
      await t.scrollUntilVisible(
        find.text('Gone quiet'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(t.takeException(), isNull);
      expect(find.text('Gone quiet'), findsOneWidget);
      await scrollToEnd(t);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('Person page fits a narrow phone, $name', (t) async {
      final d = PersonDetail(
        summary: summary(loops: loops),
        members: const ['k'],
        lastLine: 'Last message today, 11:01 AM',
        timeline: [
          TimelineLine(text: 'Hello ' * 40, at: now, mine: false, source: 'Whatsapp'),
          TimelineLine(text: 'ok 🙏', at: now, mine: true, source: 'Whatsapp', via: 'via Echo'),
        ],
        groups: const [
          SharedGroup(title: 'A very long group name indeed oh yes', source: 'Whatsapp', newToday: 12, lastLine: 'Rohan: see you'),
        ],
        choices: const PersonChoices(dontNudge: false, watching: true),
        replyTo: RawData()
          ..source = 'Whatsapp'
          ..sender = longName
          ..content = ''
          ..timestamp = now
          ..thread = 't',
        followUp: loops.owes.first,
        retentionDays: 7,
      );
      await pump(
        t,
        PersonScreen(personKey: 'k', loader: (_, _) async => d),
        theme: theme,
      );
      expect(t.takeException(), isNull);
      await scrollToEnd(t);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('A person with nothing owed hides that side, $name', (t) async {
      final d = PersonDetail(
        summary: summary(),
        members: const ['k'],
        lastLine: '',
        timeline: const [],
        groups: const [],
        choices: const PersonChoices(dontNudge: true, watching: false),
        replyTo: null,
        followUp: null,
        retentionDays: 7,
      );
      await pump(
        t,
        PersonScreen(personKey: 'k', loader: (_, _) async => d),
        theme: theme,
      );
      expect(t.takeException(), isNull);
      expect(find.textContaining('owes you'), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('Group page fits and says when nothing is heard, $name', (t) async {
      final line = GroupLine(
        key: 'k',
        sender: longName,
        source: 'Whatsapp',
        text: 'Everyone send ₹850 by Thursday pls',
        at: now,
        thread: 't',
        title: 'College gang',
        addressed: 'group',
      );
      final page = GroupPage(
        title: 'College gang with a long name that wraps',
        source: 'Whatsapp',
        lines: [line],
        digest: digestGroup([line], const [], now),
        newSinceYesterday: 214,
        pullsOut: true,
        retentionDays: 7,
        cloud: false,
      );
      await pump(
        t,
        GroupScreen(threadTitle: 'x', loader: (_, _) async => page),
        theme: theme,
      );
      expect(t.takeException(), isNull);
      await scrollToEnd(t);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());

      final none = GroupPage(
        title: 'Silent group',
        source: null,
        lines: const [],
        digest: digestGroup(const [], const [], now),
        newSinceYesterday: 0,
        pullsOut: true,
        retentionDays: 7,
        cloud: false,
      );
      await pump(
        t,
        GroupScreen(threadTitle: 'x', loader: (_, _) async => none),
        theme: theme,
      );
      expect(t.takeException(), isNull);
      expect(find.textContaining('hasn’t heard from'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });
  }
}

