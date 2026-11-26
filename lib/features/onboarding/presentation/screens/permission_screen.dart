import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/core/presentation/widgets/echo_button.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/onboarding/presentation/cubit/on_boarding_cubit.dart';
import 'package:project_echo/features/onboarding/presentation/widgets/access_preview.dart';
import 'package:project_echo/features/onboarding/presentation/widgets/permission_tile.dart';
import 'package:project_echo/features/onboarding/presentation/widgets/onboarding_scaffold.dart';
import 'package:material_symbols_icons/symbols.dart';

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
          subtitle: 'First, a taste of what Echo does with access.',
          footer: EchoButton(
            text: 'Continue',
            showArrow: true,
            onPressed: state.canContinue ? cubit.completePermissions : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AccessPreview(),
              const SizedBox(height: 14),
              const _PrivacyLine(),
              const SizedBox(height: 6),
              PermissionTile(
                icon: Symbols.notifications_active_rounded,
                title: 'Notification access',
                subtitle: 'Reads your incoming notifications',
                isGranted: state.notificationGranted,
                onChanged: (val) => cubit.toggleNotification(),
              ),
              PermissionTile(
                icon: Symbols.calendar_today_rounded,
                title: 'Calendar',
                subtitle: "Reads today's schedule",
                isGranted: state.calendarGranted,
                onChanged: (val) => cubit.toggleCalendar(),
              ),
              PermissionTile(
                icon: Symbols.alarm_rounded,
                title: 'Briefing and reminders',
                subtitle: 'Lets Echo notify you on time',
                isGranted: state.alertsGranted,
                onChanged: (val) => cubit.toggleAlerts(),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}

/// The one honest line on privacy. True as written: notifications are read
/// and kept on the phone; they leave it only for the cloud engine (Gemini)
/// or a computer the owner pairs, both their choice.
class _PrivacyLine extends StatelessWidget {
  const _PrivacyLine();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            Symbols.lock_rounded,
            size: 18,
            color: colors.primaryGreen,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Echo reads your notifications on this phone. Nothing is sent '
            'anywhere unless you choose the cloud engine or pair a computer.',
            style: GoogleFonts.nunito(
              fontSize: 14,
              height: 1.45,
              color: colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
