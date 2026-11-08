import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/demo/demo_mode.dart';
import 'package:go_router/go_router.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/presentation/screens/ask_ai_screen.dart';
import 'package:project_echo/features/echo/presentation/screens/daily_briefing_screen.dart';
import 'package:project_echo/features/echo/presentation/screens/groups_screen.dart';
import 'package:project_echo/features/onboarding/presentation/screens/start_screen.dart';
import 'package:project_echo/core/presentation/screens/main_scaffold.dart';
import 'package:project_echo/core/presentation/animations/page_transitions.dart';
import 'package:project_echo/features/people/presentation/screens/group_screen.dart';
import 'package:project_echo/features/people/presentation/screens/person_screen.dart';
import 'package:project_echo/features/profile/presentation/screens/desktop_screen.dart';
import 'package:project_echo/features/profile/presentation/screens/hears_screen.dart';
import 'package:project_echo/features/profile/presentation/screens/streak_screen.dart';
import 'package:project_echo/features/quiet/presentation/screens/digest_screen.dart';
import 'package:project_echo/features/quiet/presentation/screens/quiet_screen.dart';
import 'package:project_echo/features/settings/presentation/screens/scan_desktop_screen.dart';
import 'package:project_echo/features/settings/presentation/screens/settings_screen.dart';
import 'package:project_echo/features/todo/presentation/screens/todo_screen.dart';
import 'package:project_echo/features/widgets/presentation/screens/widgets_screen.dart';

GoRouter createRouter(bool isOnboardingFinished) => GoRouter(
  // The filming build can open on a given screen (ECHO_START=/vault).
  initialLocation: kEchoDemo && Platform.environment['ECHO_START'] != null
      ? Platform.environment['ECHO_START']!
      : (isOnboardingFinished ? '/echo' : '/'),
  routes: [
    GoRoute(
      path: '/',
      // No transition: the phone's splash already shows its first frame (see
      // LaunchEcho), so it must simply be there when the splash lifts.
      pageBuilder: (context, state) =>
          NoTransitionPage(key: state.pageKey, child: const StartScreen()),
    ),
    GoRoute(
      path: '/echo/chat',
      pageBuilder: (context, state) => slideUpPage(
        key: state.pageKey,
        // A question to ask, or a message to draft a reply to.
        child: AskAiScreen(
          initialQuestion: state.extra is String ? state.extra as String : null,
          replyTo: state.extra is RawData ? state.extra as RawData : null,
        ),
      ),
    ),
    GoRoute(
      path: '/scan-desktop',
      pageBuilder: (context, state) =>
          slideUpPage(key: state.pageKey, child: const ScanDesktopScreen()),
    ),
    // The Vault became the sheet of what Echo hears, under You.
    GoRoute(path: '/vault', redirect: (context, state) => '/you/hears'),
    _pushed('/todo', tab: '/echo', (state) => const TodoScreen()),
    _pushed('/groups', tab: '/echo', (state) => const GroupsScreen()),
    _pushed(
      '/briefing',
      tab: '/echo',
      (state) => DailyBriefingScreen(
        mode: state.extra is String ? state.extra as String : 'morning',
      ),
    ),
    _pushed('/quiet', tab: '/echo', (state) => const QuietScreen()),
    _pushed('/digest', tab: '/echo', (state) => const DigestScreen()),
    _pushed(
      '/person',
      tab: '/people',
      // A person is always named by the caller; without one there's nothing
      // to show, so go to the list.
      redirect: (context, state) => state.extra is String ? null : '/people',
      (state) => PersonScreen(personKey: state.extra as String),
    ),
    _pushed(
      '/group',
      tab: '/people',
      redirect: (context, state) => state.extra is String ? null : '/groups',
      (state) => GroupScreen(threadTitle: state.extra as String),
    ),
    _pushed('/you/hears', tab: '/profile', (state) => const HearsScreen()),
    _pushed('/you/streak', tab: '/profile', (state) => const StreakScreen()),
    _pushed('/you/widgets', tab: '/profile', (state) => const WidgetsScreen()),
    _pushed('/you/desktop', tab: '/profile', (state) => const DesktopScreen()),
    _pushed('/settings', tab: '/profile', (state) => const SettingsScreen()),
    // MainScaffold draws the tabs itself (a FadeIndexedStack keyed
    // off the location), so these pages are empty: they only give the shell
    // Navigator a route per tab. That Navigator must still be mounted —
    // go_router looks it up on every back press and pop.
    ShellRoute(
      builder: (context, state, child) {
        return MainScaffold(child: child);
      },
      routes: [
        for (final tab in const ['/echo', '/people', '/history', '/profile'])
          GoRoute(
            path: tab,
            pageBuilder: (context, state) =>
                NoTransitionPage(key: state.pageKey, child: const SizedBox()),
          ),
      ],
    ),
  ],
);

/// A screen pushed over the tabs. [tab] is the one it belongs to, for when
/// there's nothing under it to go back to (see [_Rooted]).
GoRoute _pushed(
  String path,
  Widget Function(GoRouterState state) screen, {
  required String tab,
  GoRouterRedirect? redirect,
}) => GoRoute(
  path: path,
  redirect: redirect,
  pageBuilder: (context, state) => fadeThroughPage(
    key: state.pageKey,
    child: _Rooted(
      tab: tab,
      location: state.uri.toString(),
      extra: state.extra,
      child: screen(state),
    ),
  ),
);

/// Makes sure a pushed screen has the tabs under it. Pushed as normal, they
/// already are; reached with `go` or a launch link, it would be the whole
/// stack and back would leave the app. So the stack is rebuilt: the tab,
/// then this screen on top.
class _Rooted extends StatefulWidget {
  final String tab;
  final String location;
  final Object? extra;
  final Widget child;

  const _Rooted({
    required this.tab,
    required this.location,
    required this.extra,
    required this.child,
  });

  @override
  State<_Rooted> createState() => _RootedState();
}

class _RootedState extends State<_Rooted> {
  bool _rerooting = false;

  void _reroot(GoRouter router) {
    _rerooting = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      router.go(widget.tab);
      // Once the tab is the new stack, to push on top of it.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => router.push(widget.location, extra: widget.extra),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (ModalRoute.of(context)?.isFirst ?? false) {
      if (!_rerooting) _reroot(GoRouter.of(context));
      return ColoredBox(color: context.colors.background);
    }
    return widget.child;
  }
}
