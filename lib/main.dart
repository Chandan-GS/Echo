import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:project_echo/core/presentation/launch_wake.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/features/onboarding/presentation/cubit/on_boarding_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_echo/core/routes/app_router.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_state.dart';
import 'package:go_router/go_router.dart';
import 'package:project_echo/features/echo/data/services/notification_service.dart';
import 'package:project_echo/core/services/schedule_service.dart';
import 'package:project_echo/core/services/local_notification_service.dart';
import 'package:project_echo/core/services/echo_server_service.dart';
import 'package:project_echo/core/services/analytics_service.dart';
import 'package:project_echo/core/services/remote_config_service.dart';
import 'package:aptabase_flutter/aptabase_flutter.dart';
import 'dart:async';
import 'package:project_echo/demo/demo_mode.dart';
import 'package:project_echo/core/services/reminder_settings.dart';

void main() async {
  GoogleFonts.config.allowRuntimeFetching = false;
  WidgetsFlutterBinding.ensureInitialized();

  // The filming build starts on its scripted day every launch.
  await DemoSeed.seed();

  // Anonymous, opt-out usage analytics — no account, no PII, no user content.
  // Only counts how often features are used (see Analytics / analytics_service).
  // Never from the demo build.
  if (!kEchoDemo) await Aptabase.init('A-US-1016715353');
  await Analytics.load();

  // Fetch the remote Gemini model name in the background — never blocks launch;
  // the cloud model isn't used until the user acts, by which time this resolves.
  unawaited(RemoteConfigService.instance.load());
  // Echo is a portrait-only experience — lock it so layouts never have to
  // reflow into landscape.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  final prefs = await SharedPreferences.getInstance();
  await ReminderSettings.load();
  final isOnboardingFinished = prefs.getBool('onboarding_finished') ?? false;

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

  // Onboarding is never re-entered once finished. A missing on-device model is
  // handled in-feature: the briefing and Ask Echo prompt the user to download
  // it or switch to the cloud engine.

  // The demo neither listens to the device's notifications nor schedules
  // briefings: its day is scripted.
  if (!kEchoDemo) {
    await NotificationService.instance.initialize();

    await ScheduleService.initialize();
    final briefingTimes = prefs.getStringList('briefing_times') ?? ['07:00'];
    await ScheduleService.updateSchedules(briefingTimes);
  }

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

  final app = Echo(isOnboardingFinished: isOnboardingFinished);
  // Filming on a computer: a moment of plain ground first, so the window is
  // up before Echo draws, and its entrance can be recorded from the start.
  final curtain = kEchoDemo && (Platform.isMacOS || Platform.isWindows);
  runApp(curtain ? _Curtain(child: app) : app);
}

class _Curtain extends StatefulWidget {
  final Widget child;
  const _Curtain({required this.child});

  @override
  State<_Curtain> createState() => _CurtainState();
}

class _CurtainState extends State<_Curtain> {
  bool _up = true;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _up = false);
    });
  }

  @override
  Widget build(BuildContext context) =>
      _up ? const ColoredBox(color: Color(0xFF1A1A1A)) : widget.child;
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
            // The phone's splash shows Echo asleep; once set up, he wakes
            // there and fades into Home. (First time, the welcome screen
            // starts from that same frame instead.)
            builder: isOnboardingFinished && Platform.isAndroid
                ? (context, child) => LaunchWake(child: child!)
                : null,
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
