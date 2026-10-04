import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:project_echo/demo/demo_mode.dart';
import 'package:go_router/go_router.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/presentation/screens/ask_ai_screen.dart';
import 'package:project_echo/features/onboarding/presentation/screens/start_screen.dart';
import 'package:project_echo/core/presentation/screens/main_scaffold.dart';
import 'package:project_echo/core/presentation/animations/page_transitions.dart';
import 'package:project_echo/features/settings/presentation/screens/scan_desktop_screen.dart';

GoRouter createRouter(bool isOnboardingFinished) => GoRouter(
  // The filming build can open on a given tab (ECHO_START=/vault).
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
    // MainScaffold draws the tabs itself (a FadeIndexedStack keyed
    // off the location), so these pages are empty: they only give the shell
    // Navigator a route per tab. That Navigator must still be mounted —
    // go_router looks it up on every back press and pop.
    ShellRoute(
      builder: (context, state, child) {
        return MainScaffold(child: child);
      },
      routes: [
        GoRoute(
          path: '/echo',
          pageBuilder: (context, state) =>
              NoTransitionPage(key: state.pageKey, child: const SizedBox()),
        ),
        GoRoute(
          path: '/todo',
          pageBuilder: (context, state) =>
              NoTransitionPage(key: state.pageKey, child: const SizedBox()),
        ),
        GoRoute(
          path: '/vault',
          pageBuilder: (context, state) =>
              NoTransitionPage(key: state.pageKey, child: const SizedBox()),
        ),
        // The Profile tab holds the streak calendar + all app settings.
        GoRoute(
          path: '/profile',
          pageBuilder: (context, state) =>
              NoTransitionPage(key: state.pageKey, child: const SizedBox()),
        ),
      ],
    ),
  ],
);
