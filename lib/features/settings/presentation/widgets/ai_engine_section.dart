import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/services/offline_model_repository.dart';
import 'package:project_echo/features/onboarding/presentation/widgets/ai_mode_card.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_state.dart';
import 'package:project_echo/features/settings/presentation/widgets/cloud_engine_card.dart';
import 'package:project_echo/features/settings/presentation/widgets/model_management_section.dart';

/// Where Echo thinks: the offline model or the cloud, and the offline
/// model's download.
class AiEngineSection extends StatelessWidget {
  const AiEngineSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BlocBuilder<SettingsCubit, SettingsState>(
          builder: (context, state) {
            return FutureBuilder<String?>(
              future: _getModelSize(),
              builder: (context, snapshot) {
                final sizeStr = snapshot.data;
                return AiModeCard(
                  isSelected: state.isOfflineEngine,
                  icon: Symbols.laptop_mac_rounded,
                  title: 'Offline (Private)',
                  tags: [
                    offlineModelDisplayName(),
                    sizeStr ?? offlineModelSizeLabel(),
                    'No API cost',
                  ],
                  speedLabel: 'Fast',
                  isFast: true,
                  onTap: () {
                    context.read<SettingsCubit>().setAiEngine(isOffline: true);
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
    );
  }

  static Future<String?> _getModelSize() async {
    try {
      final path = await createOfflineModelRepository().downloadedPathOrNull();
      if (path != null) {
        final bytes = await File(path).length();
        final gb = bytes / (1024 * 1024 * 1024);
        return '${gb.toStringAsFixed(1)} GB';
      }
    } catch (e) {
      // Ignore
    }
    return null;
  }
}
