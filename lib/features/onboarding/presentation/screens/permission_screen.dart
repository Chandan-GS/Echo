import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/core/presentation/widgets/echo_button.dart';
import 'package:project_echo/features/onboarding/presentation/cubit/on_boarding_cubit.dart';
import 'package:project_echo/features/onboarding/presentation/widgets/permission_tile.dart';
import 'package:project_echo/features/onboarding/presentation/widgets/onboarding_scaffold.dart';

class PermissionScreen extends StatefulWidget {
  const PermissionScreen({super.key});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<OnBoardingCubit>().checkPermissions();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<OnBoardingCubit>();

    return BlocBuilder<OnBoardingCubit, OnBoardingState>(
      builder: (context, state) {
        if (state is! PermissionsStep) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return OnboardingStepBody(
          title: 'Connect your world to Echo.',
          subtitle:
              'Read on-device to build your briefing. Nothing leaves your '
              'phone unless you choose Cloud AI.',
          footer: EchoButton(
            text: 'Continue',
            showArrow: true,
            onPressed: state.canContinue ? cubit.completePermissions : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PermissionTile(
                icon: Icons.notifications_active_outlined,
                title: 'Notification access',
                subtitle: 'Reads incoming alerts',
                isGranted: state.notificationGranted,
                onChanged: (val) => cubit.toggleNotification(),
              ),
              PermissionTile(
                icon: Icons.calendar_today_outlined,
                title: 'Calendar',
                subtitle: "Reads today's schedule",
                isGranted: state.calendarGranted,
                onChanged: (val) => cubit.toggleCalendar(),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}
