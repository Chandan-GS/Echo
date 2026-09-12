import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/features/onboarding/presentation/cubit/on_boarding_cubit.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_state.dart';
import 'package:project_echo/features/onboarding/presentation/widgets/ai_mode_card.dart';
import 'package:project_echo/features/settings/presentation/widgets/appearance_segmented_control.dart';
import 'package:project_echo/features/settings/presentation/widgets/cloud_engine_card.dart';
import 'package:project_echo/features/settings/presentation/widgets/scheduled_briefings_section.dart';
import 'package:project_echo/features/settings/presentation/widgets/voice_settings_section.dart';
import 'package:project_echo/features/settings/presentation/widgets/tone_settings_section.dart';
import 'package:project_echo/features/settings/presentation/widgets/model_management_section.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/presentation/animations/fade_slide_in.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const _SettingsView();
  }
}

class _SettingsView extends StatelessWidget {
  const _SettingsView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              FadeSlideIn(
                child: Text(
                  'Settings',
                  style: GoogleFonts.oldStandardTt(
                    fontSize: 40,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
                    height: 1.15,
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Appearance Section
              FadeSlideIn(
                delay: AppMotion.staggerDelay(1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Appearance',
                      style: GoogleFonts.nunito(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: context.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const AppearanceSegmentedControl(),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Voice Section
              FadeSlideIn(
                delay: AppMotion.staggerDelay(2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Voice',
                      style: GoogleFonts.nunito(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: context.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'How Echo sounds when it reads your briefing.',
                      style: GoogleFonts.nunito(
                        fontSize: 14,
                        color: context.colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const VoiceSettingsSection(),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Tone Section
              FadeSlideIn(
                delay: AppMotion.staggerDelay(3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tone',
                      style: GoogleFonts.nunito(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: context.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'How Echo talks to you in every briefing.',
                      style: GoogleFonts.nunito(
                        fontSize: 14,
                        color: context.colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const ToneSettingsSection(),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // AI Engine Section
              FadeSlideIn(
                delay: AppMotion.staggerDelay(3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Engine',
                      style: GoogleFonts.nunito(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: context.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    BlocBuilder<SettingsCubit, SettingsState>(
                      builder: (context, state) {
                        return FutureBuilder<String?>(
                          future: _getModelSize(),
                          builder: (context, snapshot) {
                            final sizeStr = snapshot.data;
                            return AiModeCard(
                              isSelected: state.isOfflineEngine,
                              icon: Icons.laptop_mac,
                              title: 'Offline (Private)',
                              tags: [
                                'Qwen2.5 1.5B',
                                sizeStr ?? '0.9 GB',
                                'No API cost',
                              ],
                              speedLabel: 'Fast',
                              isFast: true,
                              onTap: () {
                                context.read<SettingsCubit>().setAiEngine(
                                  isOffline: true,
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                    const CloudEngineCard(),
                    const SizedBox(height: 16),
                    const ModelManagementSection(),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Scheduled Briefings Section
              FadeSlideIn(
                delay: AppMotion.staggerDelay(4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Scheduled Briefings',
                      style: GoogleFonts.nunito(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: context.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const ScheduledBriefingsSection(),
                  ],
                ),
              ),
              // Debug-only: jump back into the onboarding flow for testing.
              if (kDebugMode) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('onboarding_finished', false);
                      if (!context.mounted) return;
                      context.read<OnBoardingCubit>().startOnboarding();
                      context.go('/');
                    },
                    icon: const Icon(Icons.replay_rounded, size: 18),
                    label: const Text('Replay onboarding (debug)'),
                    style: TextButton.styleFrom(
                      foregroundColor: context.colors.textSecondary,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 120), // Padding for the bottom nav bar
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _getModelSize() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final modelPath = '${dir.path}/qwen2.5_1.5b_instruct_q3_k_m.gguf';
      final file = File(modelPath);
      if (await file.exists()) {
        final bytes = await file.length();
        final gb = bytes / (1024 * 1024 * 1024);
        return '${gb.toStringAsFixed(1)} GB';
      }
    } catch (e) {
      // Ignore
    }
    return null;
  }
}
