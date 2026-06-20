import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:project_echo/features/onboarding/presentation/cubit/on_boarding_cubit.dart';
import 'package:project_echo/features/onboarding/presentation/screens/permission_screen.dart';
import 'package:project_echo/features/onboarding/presentation/screens/ai_mode_screen.dart';
import 'package:project_echo/features/onboarding/presentation/screens/welcome_screen.dart';
import 'package:project_echo/features/echo/presentation/screens/echo_home_screen.dart';

class StartScreen extends StatelessWidget {
  const StartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<OnBoardingCubit, OnBoardingState>(
      listener: (context, state) {
        if (state is OnBoardingFinished) {
          context.go('/echo');
        }
      },
      builder: (context, state) {
        if (state is OnBoardingInitial) {
          return const WelcomeScreen();
        } else if (state is PermissionsStep) {
          return const PermissionScreen();
        } else if (state is AiModeStep) {
          return const AiModeScreen();
        } else if (state is OnBoardingFinished) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        return const Scaffold(body: Center(child: Text('Unknown State')));
      },
    );
  }
}
