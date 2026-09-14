import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/features/onboarding/presentation/cubit/on_boarding_cubit.dart';
import 'package:project_echo/features/onboarding/presentation/screens/permission_screen.dart';
import 'package:project_echo/features/onboarding/presentation/screens/ai_mode_screen.dart';
import 'package:project_echo/features/onboarding/presentation/screens/welcome_screen.dart';
import 'package:project_echo/features/onboarding/presentation/screens/name_input_screen.dart';
import 'package:project_echo/features/onboarding/presentation/screens/personalize_screen.dart';
import 'package:project_echo/features/onboarding/presentation/screens/voice_screen.dart';
import 'package:project_echo/features/onboarding/presentation/screens/preview_screen.dart';
import 'package:project_echo/features/onboarding/presentation/widgets/onboarding_scaffold.dart';

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
        // Two-level animation: the OUTER switcher only ever crosses between the
        // full-bleed welcome and the persistent shell (so the shell — back
        // button + progress bar — mounts once and survives every step). The
        // INNER switcher, inside the shell, cross-fades the step bodies. The
        // chrome therefore never re-mounts; the progress bar just animates its
        // fill.
        final Widget top;
        if (state is OnBoardingInitial) {
          top = const WelcomeScreen(key: ValueKey('welcome'));
        } else if (state is OnBoardingFinished) {
          top = const ColoredBox(
            key: ValueKey('done'),
            color: Colors.transparent,
          );
        } else {
          top = OnboardingShell(
            key: const ValueKey('shell'),
            step: _stepFor(state),
            onBack: _onBackFor(context, state),
            body: AnimatedSwitcher(
              duration: AppMotion.medium,
              switchInCurve: AppMotion.emphasized,
              switchOutCurve: AppMotion.standard,
              transitionBuilder: _fadeSlide,
              layoutBuilder: (currentChild, previousChildren) => Stack(
                alignment: Alignment.topCenter,
                children: [...previousChildren, ?currentChild],
              ),
              child: KeyedSubtree(
                key: ValueKey(state.runtimeType),
                child: _bodyForState(state),
              ),
            ),
          );
        }

        return AnimatedSwitcher(
          duration: AppMotion.medium,
          switchInCurve: AppMotion.emphasized,
          switchOutCurve: AppMotion.standard,
          transitionBuilder: _fadeSlide,
          child: top,
        );
      },
    );
  }

  static Widget _fadeSlide(Widget child, Animation<double> animation) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.03),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }

  int _stepFor(OnBoardingState state) => switch (state) {
    PermissionsStep() => 1,
    AiModeStep() => 2,
    NameInputStep() => 3,
    PersonalizeStep() => 4,
    VoiceStep() => 5,
    PreviewStep() => 6,
    _ => 1,
  };

  VoidCallback? _onBackFor(BuildContext context, OnBoardingState state) {
    final cubit = context.read<OnBoardingCubit>();
    // On desktop, completeWelcome() skips PermissionsStep entirely (see
    // OnBoardingCubit), so going back from AiModeStep must return to Welcome
    // rather than re-entering a step that's never shown there.
    final isDesktop = Platform.isMacOS || Platform.isWindows;
    return switch (state) {
      PermissionsStep() => cubit.startOnboarding,
      AiModeStep() =>
        isDesktop ? cubit.startOnboarding : cubit.checkPermissions,
      NameInputStep() => cubit.goBackToAiMode,
      PersonalizeStep() => cubit.goBackToName,
      VoiceStep() => cubit.goBackToPersonalize,
      PreviewStep() => cubit.goBackToVoice,
      _ => null,
    };
  }

  Widget _bodyForState(OnBoardingState state) {
    return switch (state) {
      PermissionsStep() => const PermissionScreen(),
      AiModeStep() => const AiModeScreen(),
      NameInputStep() => const NameInputScreen(),
      PersonalizeStep() => const PersonalizeScreen(),
      VoiceStep() => const VoiceScreen(),
      PreviewStep(:final name, :final tone, :final interests, :final voice) =>
        PreviewScreen(
          name: name,
          tone: tone,
          interests: interests,
          voice: voice,
        ),
      _ => const SizedBox.shrink(),
    };
  }
}
