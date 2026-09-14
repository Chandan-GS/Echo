import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/features/onboarding/presentation/cubit/on_boarding_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_echo/core/routes/app_router.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_state.dart';
import 'package:go_router/go_router.dart';
import 'package:project_echo/features/onboarding/data/repositories/model_download_repository_impl.dart';
import 'package:project_echo/features/echo/data/services/notification_service.dart';
import 'package:project_echo/core/services/schedule_service.dart';
import 'package:project_echo/core/services/local_notification_service.dart';
import 'package:project_echo/core/services/echo_server_service.dart';

void main() async {
  GoogleFonts.config.allowRuntimeFetching = false;
  WidgetsFlutterBinding.ensureInitialized();
  // Echo is a portrait-only experience — lock it so layouts never have to
  // reflow into landscape.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  final prefs = await SharedPreferences.getInstance();
  bool isOnboardingFinished = prefs.getBool('onboarding_finished') ?? false;

  // Stamp the first-ever launch so the Profile screen can show "Member for N
  // days". Set once, never overwritten.
  if (prefs.getString('first_launch_date') == null) {
    await prefs.setString(
      'first_launch_date',
      DateTime.now().toIso8601String(),
    );
  }

  // Register the daily-briefing notification's tap handlers for this process
  // (covers taps while the app is alive), and detect a cold start caused by
  // tapping the notification body itself (the background-action case is
  // handled separately by `notificationTapBackgroundHandler`) — either way,
  // marks today's briefing to autoplay once EchoHomeScreen loads it.
  final localNotifications = LocalNotificationService();
  await localNotifications.init();
  final launchDetails = await localNotifications.flutterLocalNotificationsPlugin
      .getNotificationAppLaunchDetails();
  if (launchDetails?.didNotificationLaunchApp ?? false) {
    await prefs.setBool('pending_autoplay', true);
  }

  // Note: notification permission is requested in-context during onboarding
  // (the Permissions step), not abruptly at cold start.

  // Only the offline engine needs the local model on disk. Cloud (Gemini)
  // users legitimately finish onboarding without ever downloading it, and
  // offline users may still be downloading it in the background — so guard on
  // the selected engine and use the same size-validated check as the download
  // repository. Otherwise these users get forced back through onboarding on
  // every launch.
  if (isOnboardingFinished) {
    final isOfflineEngine = prefs.getBool('is_offline_engine') ?? true;
    if (isOfflineEngine &&
        !(await ModelDownloadRepositoryImpl().isModelDownloaded())) {
      isOnboardingFinished = false;
      await prefs.setBool('onboarding_finished', false);
    }
  }

  await NotificationService.instance.initialize();

  await ScheduleService.initialize();
  final briefingTimes = prefs.getStringList('briefing_times') ?? ['07:00'];
  await ScheduleService.updateSchedules(briefingTimes);

  // Desktop-only, off by default: resume the Echo Engine service on launch if
  // the user previously turned it on for this machine. Starts regardless of
  // whether the model has finished downloading — the server is discoverable
  // immediately either way, and resolves the model fresh on every request
  // rather than needing it present at startup.
  if (Platform.isMacOS || Platform.isWindows) {
    final runHere = prefs.getBool('run_desktop_engine_here') ?? false;
    if (runHere) {
      await EchoServerService.instance.start();
    }
  }

  runApp(Echo(isOnboardingFinished: isOnboardingFinished));
}

class Echo extends StatelessWidget {
  final bool isOnboardingFinished;
  late final GoRouter _router;

  Echo({super.key, required this.isOnboardingFinished}) {
    _router = createRouter(isOnboardingFinished);
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) =>
              OnBoardingCubit(isFinished: isOnboardingFinished),
        ),
        BlocProvider(create: (context) => SettingsCubit()),
      ],
      child: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, state) {
          return MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: state.themeMode,
            // Desktop platforms auto-decorate every scrollable with a visible
            // drag-scrollbar by default — reads as a stray UI chrome element
            // rather than an intentional part of the design. Suppress it app-
            // wide; touch/trackpad scrolling still works exactly as before.
            scrollBehavior: _NoScrollbarBehavior(),
            routerConfig: _router,
          );
        },
      ),
    );
  }
}

class _NoScrollbarBehavior extends MaterialScrollBehavior {
  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}
