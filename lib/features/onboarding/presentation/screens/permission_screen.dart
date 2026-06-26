import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/core/presentation/widgets/echo_button.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/features/onboarding/presentation/cubit/on_boarding_cubit.dart';
import 'package:project_echo/core/presentation/widgets/chip_label.dart';
import 'package:project_echo/features/onboarding/presentation/widgets/permission_tile.dart';

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

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: context.colors.textPrimary,
              ),
              onPressed: () {
                cubit.startOnboarding();
              },
            ),
          ),
          backgroundColor: context.colors.background,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 16.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Echo needs to listen quietly.',
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      color: context.colors.textPrimary,
                      fontSize: 28,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Description with "choose it" wrapped in a light green pill
                  RichText(
                    text: TextSpan(
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: context.colors.textSecondary,
                        height: 1.5,
                      ),
                      children: [
                        const TextSpan(
                          text:
                              'No data is collected from the app. Your data stays entirely on your device, and is only sent to ',
                        ),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: ChipLabel(
                            text: 'Cloud AI',
                            backgroundColor:
                                context.colors.lightGreenBackground,
                            textColor: Colors.black,
                            isOutline: false,
                          ),
                        ),
                        const TextSpan(text: ' if you choose it.'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Permission Tiles
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

                  const Spacer(),

                  // Continue Button
                  EchoButton(
                    text: 'Continue',
                    onPressed: state.canContinue
                        ? () {
                            cubit.completePermissions();
                          }
                        : null,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
