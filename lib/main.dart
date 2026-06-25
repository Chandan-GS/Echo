import 'package:flutter/material.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/features/onboarding/presentation/cubit/on_boarding_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_echo/core/routes/app_router.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_state.dart';
import 'package:go_router/go_router.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:project_echo/features/echo/data/services/notification_service.dart';
import 'package:project_echo/core/services/schedule_service.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  bool isOnboardingFinished = prefs.getBool('onboarding_finished') ?? false;
  if (Platform.isAndroid) {
    final status = await Permission.notification.status;
    if (status.isDenied) {
      await Permission.notification.request();
    }
  }

  // Safety check: if they completed onboarding but the model is missing, force them back to onboarding!
  if (isOnboardingFinished) {
    final dir = await getApplicationDocumentsDirectory();
    final modelPath = '${dir.path}/qwen2.5_1.5b_instruct_q3_k_m.gguf';
    if (!(await File(modelPath).exists())) {
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
