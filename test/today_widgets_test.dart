import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/features/echo/data/context/chat_context_store.dart';
import 'package:project_echo/features/echo/data/home/home_feed.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/waiting/waiting_store.dart';
import 'package:project_echo/features/echo/presentation/cubit/briefing_cubit.dart';
import 'package:project_echo/features/echo/presentation/widgets/today/today_glance.dart';
import 'package:project_echo/features/echo/presentation/widgets/today/today_parts.dart';
import 'package:project_echo/features/echo/presentation/widgets/today/today_sections.dart';
import 'package:project_echo/features/echo/presentation/widgets/today/waiting_card.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:project_echo/features/todo/presentation/cubit/todo_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

final now = DateTime(2026, 11, 8, 16, 12);

RawData msg(String sender, String content, DateTime when) => RawData()
  ..source = 'WhatsApp'
  ..sender = sender
  ..content = content
  ..timestamp = when
  ..thread = 'com.whatsapp:$sender'
  ..threadTitle = sender
  ..isGroup = false
  ..addressed = 'direct';

Widget frame(Widget child, {required bool dark, required double scale}) =>
    MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => BriefingCubit()),
        BlocProvider(create: (_) => TodoCubit()),
        BlocProvider(create: (_) => SettingsCubit()),
      ],
      child: MaterialApp(
        theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(320, 900),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: child,
            ),
          ),
        ),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final long = 'Rajeshwari Venkataraghavan from the accounts department';
  final feed = WaitingStore.compose(
    [
      msg(
        'Amma',
        'Call when free. Electricity bill is due tomorrow.',
        now.subtract(const Duration(days: 2)),
      ),
      msg(
        long,
        'Can you share the Figma link before the 4 o’clock review? ' * 8,
        now.subtract(const Duration(minutes: 40)),
      ),
      msg(
        '🔥 प्रिया',
        'report भेज दो जल्दी 🙏',
        now.subtract(const Duration(hours: 20)),
      ),
    ],
    const MyTurns({}),
    now,
  );
  final acks = WaitingStore.compose(
    [msg(long, 'ok thanks', now.subtract(const Duration(minutes: 2)))],
    const MyTurns({}),
    now,
  );
  final groups = [
    BusyGroup(
      name: 'Prestige Lakeside residents association, phase two',
      count: 88,
      needs: true,
      messages: [msg('Riya', 'Water supply off Sunday 10 to 2', now)],
    ),
    BusyGroup(
      name: 'Family',
      count: 12,
      messages: [msg('Dad', 'Good morning', now)],
    ),
  ];

  for (final dark in [false, true]) {
    // The test font's letters are about twice as wide as Nunito's.
    for (final scale in [1.0, 1.25]) {
      testWidgets('lays out at 320 dp, dark $dark, text x$scale', (t) async {
        t.view.physicalSize = const Size(320, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await t.pumpWidget(
          frame(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TodayHeader(now: now, quietOn: true, onQuiet: () {}),
                TodayGlance(now: now, waiting: 3, name: 'Chandan'),
                const TodaySectionHead('Waiting on you', note: '3 people'),
                for (final (i, w) in feed.waiting.indexed)
                  WaitingCard(
                    item: w,
                    index: i,
                    onGone: () {},
                    onHandled: () {},
                  ),
                AcksRow(acks: acks.acks),
                const TodoSection(),
                BusyGroupsSection(groups: groups, summaries: const {}),
                const AllClearCard(),
                NoAccessCard(onGrant: () {}),
              ],
            ),
            dark: dark,
            scale: scale,
          ),
        );
        await t.pump(const Duration(milliseconds: 500));
        expect(t.takeException(), isNull);
        await t.pump(const Duration(seconds: 2));
      });
    }
  }

  test('the waiting list is shaped as the screens expect', () {
    expect(feed.waiting.first.message.sender, 'Amma');
    expect(feed.waiting.first.ageBand, 2);
    expect(acks.acks, hasLength(1));
  });
}
