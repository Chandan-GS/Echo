import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/core/presentation/widgets/echo_button.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
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
              PermissionTile(
                icon: Icons.sms_outlined,
                title: 'SMS',
                subtitle: 'Reads text messages',
                isGranted: state.smsGranted,
                onChanged: (val) => cubit.toggleSms(),
              ),
              if (state.notificationGranted) ...[
                const SizedBox(height: 20),
                const _ListeningProof(),
              ],
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}

/// A small, live "Echo is listening — N signals captured" banner. Polls the
/// local Isar store so the count visibly climbs as notifications arrive,
/// turning the notification permission into immediate, tangible proof.
class _ListeningProof extends StatefulWidget {
  const _ListeningProof();

  @override
  State<_ListeningProof> createState() => _ListeningProofState();
}

class _ListeningProofState extends State<_ListeningProof> {
  int? _count;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  Future<void> _refresh() async {
    try {
      final entries = await IsarDataSource.getAllEntries();
      if (mounted) setState(() => _count = entries.length);
    } catch (_) {
      if (mounted) setState(() => _count = _count ?? 0);
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = _count;
    final String message;
    if (count == null) {
      message = 'Connecting…';
    } else if (count == 0) {
      message = "Echo is listening. I'll capture signals as they arrive.";
    } else {
      message =
          'Echo is already listening — $count signal${count == 1 ? '' : 's'} captured.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: context.colors.lightGreenBackground.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: context.colors.primaryGreen.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.colors.primaryGreen,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.nunito(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
