import 'package:flutter/material.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/features/onboarding/presentation/cubit/on_boarding_cubit.dart';
import 'package:project_echo/features/onboarding/presentation/screens/start_screen.dart';

void main() {
  runApp(const Echo());
}

class Echo extends StatelessWidget {
  const Echo({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      themeMode:
          ThemeMode.system, // Will switch based on user's device settings
      home: BlocProvider(
        create: (context) => OnBoardingCubit(),
        child: StartScreen(),
      ),
    );
  }
}
