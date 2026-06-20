import 'package:go_router/go_router.dart';
import 'package:project_echo/features/echo/presentation/screens/echo_home_screen.dart';
import 'package:project_echo/features/onboarding/presentation/screens/start_screen.dart';
import 'package:project_echo/core/presentation/screens/main_scaffold.dart';
import 'package:project_echo/features/vault/presentation/screens/vault_screen.dart';
import 'package:project_echo/features/settings/presentation/screens/settings_screen.dart';

GoRouter createRouter(bool isOnboardingFinished) => GoRouter(
  initialLocation: isOnboardingFinished ? '/echo' : '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const StartScreen()),
    ShellRoute(
      builder: (context, state, child) {
        return MainScaffold(child: child);
      },
      routes: [
        GoRoute(
          path: '/echo',
          builder: (context, state) => const EchoHomeScreen(),
        ),
        GoRoute(
          path: '/vault',
          builder: (context, state) => const VaultScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
      ],
    ),
  ],
);
