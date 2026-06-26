import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_state.dart';
import 'package:project_echo/features/onboarding/presentation/widgets/ai_mode_card.dart';
import 'package:project_echo/features/settings/presentation/widgets/appearance_segmented_control.dart';
import 'package:project_echo/features/settings/presentation/widgets/cloud_engine_card.dart';
import 'package:project_echo/features/settings/presentation/widgets/scheduled_briefings_section.dart';
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
              Text(
                'Settings',
                style: GoogleFonts.oldStandardTt(
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textPrimary,
                  height: 1.15,
                ),
              ),

              const SizedBox(height: 32),

              // Appearance Section
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
              const SizedBox(height: 32),

              // AI Engine Section
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
              const SizedBox(height: 32),

              // Scheduled Briefings Section
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
