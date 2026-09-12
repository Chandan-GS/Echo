import 'package:flutter/material.dart';
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

void main() async {
  GoogleFonts.config.allowRuntimeFetching = false;
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  bool isOnboardingFinished = prefs.getBool('onboarding_finished') ?? false;

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
            routerConfig: _router,
          );
        },
      ),
    );
  }
}
