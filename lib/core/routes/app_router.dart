import 'package:go_router/go_router.dart';
import 'package:project_echo/features/echo/presentation/screens/echo_home_screen.dart';
import 'package:project_echo/features/echo/presentation/screens/ask_ai_screen.dart';
import 'package:project_echo/features/onboarding/presentation/screens/start_screen.dart';
import 'package:project_echo/core/presentation/screens/main_scaffold.dart';
import 'package:project_echo/core/presentation/animations/page_transitions.dart';
import 'package:project_echo/features/vault/presentation/screens/vault_screen.dart';
import 'package:project_echo/features/settings/presentation/screens/settings_screen.dart';
import 'package:project_echo/features/settings/presentation/screens/scan_desktop_screen.dart';

GoRouter createRouter(bool isOnboardingFinished) => GoRouter(
  initialLocation: isOnboardingFinished ? '/echo' : '/',
  routes: [
    GoRoute(
      path: '/',
      pageBuilder: (context, state) =>
          fadeThroughPage(key: state.pageKey, child: const StartScreen()),
    ),
    GoRoute(
      path: '/echo/chat',
      pageBuilder: (context, state) =>
          slideUpPage(key: state.pageKey, child: const AskAiScreen()),
    ),
    GoRoute(
      path: '/scan-desktop',
      pageBuilder: (context, state) =>
          slideUpPage(key: state.pageKey, child: const ScanDesktopScreen()),
    ),
    ShellRoute(
      builder: (context, state, child) {
        return MainScaffold(child: child);
      },
      routes: [
        GoRoute(
          path: '/echo',
          pageBuilder: (context, state) =>
              fadeThroughPage(key: state.pageKey, child: const EchoHomeScreen()),
        ),
        GoRoute(
          path: '/vault',
          pageBuilder: (context, state) =>
              fadeThroughPage(key: state.pageKey, child: const VaultScreen()),
        ),
        // The Profile tab now holds the streak calendar + all app settings,
        // merged into one screen.
        GoRoute(
          path: '/profile',
          pageBuilder: (context, state) =>
              fadeThroughPage(key: state.pageKey, child: const SettingsScreen()),
        ),
      ],
    ),
  ],
);
