import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/animations/page_transitions.dart';
import 'package:project_echo/core/services/offline_model_repository.dart';
import 'package:project_echo/features/settings/data/engine_status.dart';
import 'package:project_echo/features/settings/data/writing_pack.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_state.dart';
import 'package:project_echo/features/settings/presentation/screens/phone_settings_screen.dart';
import 'package:project_echo/features/settings/presentation/screens/writing_pack_page.dart';
import 'package:project_echo/features/settings/presentation/widgets/scheduled_briefings_section.dart';
import 'package:project_echo/features/settings/presentation/widgets/settings_kit.dart';

/// Settings → Morning briefing: the master switch, the times, and what will
/// write it. The times are kept while it's off.
class BriefingSettingsPage extends StatelessWidget {
  const BriefingSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        final cubit = context.read<SettingsCubit>();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsSwitchCard(
              icon: Symbols.wb_twilight_rounded,
              title: 'Morning briefing',
              value: 'Echo prepares it in the background',
              on: state.briefingEnabled,
              onChanged: (on) {
                cubit.setBriefingEnabled(on);
                settingsToast(
                  context,
                  on ? 'Morning briefing on' : 'Morning briefing off',
                );
              },
            ),
            if (state.briefingEnabled) ...[
              const SettingsSubLabel('Times'),
              const ScheduledBriefingsSection(),
            ],
            const SizedBox(height: 18),
            ValueListenableBuilder<WritingPackStatus>(
              valueListenable: WritingPack.status,
              builder: (context, pack, _) {
                final engine = engineInUse(
                  isOffline: state.isOfflineEngine,
                  geminiKey: state.geminiApiKey,
                  packReady: pack.ready,
                );
                return switch (engine) {
                  EngineInUse.cloud => const SettingsHint(
                    icon: Symbols.cloud_done_rounded,
                    title: 'Using the cloud engine',
                    body: 'Briefings are written by Gemini with your key.',
                  ),
                  EngineInUse.writingPack => const SettingsHint(
                    icon: Symbols.check_circle_rounded,
                    title: 'Using the writing pack on this phone',
                    body: 'Briefings are written and read aloud offline.',
                  ),
                  EngineInUse.none => SettingsHint(
                    icon: Symbols.download_for_offline_rounded,
                    title: 'A spoken briefing needs the writing pack',
                    body:
                        'Without it, the briefing is a plain list. Get the pack '
                        '(${offlineModelSizeLabel()}) or turn on the cloud '
                        'engine.',
                    onTap: () => Navigator.of(context).push(
                      bouncyRoute(
                        const SettingsPage(
                          title: 'Writing pack',
                          subtitle: writingPackIntro,
                          child: WritingPackPage(),
                        ),
                      ),
                    ),
                  ),
                };
              },
            ),
          ],
        );
      },
    );
  }
}
