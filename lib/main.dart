import 'package:flutter/material.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/features/onboarding/presentation/cubit/on_boarding_cubit.dart';
import 'package:project_echo/features/onboarding/presentation/screens/start_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final isOnboardingFinished = prefs.getBool('onboarding_finished') ?? false;

  runApp(Echo(isOnboardingFinished: isOnboardingFinished));
}

class Echo extends StatelessWidget {
  final bool isOnboardingFinished;

  const Echo({super.key, required this.isOnboardingFinished});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      themeMode:
          ThemeMode.system, // Will switch based on user's device settings
      home: BlocProvider(
        create: (context) => OnBoardingCubit(isFinished: isOnboardingFinished),
        child: const StartScreen(),
      ),
    );
  }
}
