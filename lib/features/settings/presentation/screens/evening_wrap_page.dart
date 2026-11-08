import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_mascot.dart';
import 'package:project_echo/features/onboarding/presentation/widgets/selectable_tile.dart';
import 'package:project_echo/features/settings/data/evening_wrap.dart';
import 'package:project_echo/features/settings/data/evening_wrap_service.dart';
import 'package:project_echo/features/settings/data/schedule_prefs.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_state.dart';
import 'package:project_echo/features/settings/presentation/widgets/settings_kit.dart';

/// Settings → Evening wrap: the switch, the time, and what the notification
/// would say tonight, with tonight's real words.
class EveningWrapPage extends StatefulWidget {
  const EveningWrapPage({super.key});

  @override
  State<EveningWrapPage> createState() => _EveningWrapPageState();
}

class _EveningWrapPageState extends State<EveningWrapPage> {
  EveningWrapText? _preview;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    final text = await EveningWrapService.tonight(DateTime.now());
    if (mounted) setState(() => _preview = text);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        final cubit = context.read<SettingsCubit>();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsSwitchCard(
              icon: Symbols.bedtime_rounded,
              title: 'Evening wrap',
              value: 'Clearing it keeps your streak going',
              on: state.eveningWrapEnabled,
              onChanged: (on) {
                cubit.setEveningWrapEnabled(on);
                settingsToast(
                  context,
                  on
                      ? 'Evening wrap at ${clockLabel(state.eveningWrapTime)}'
                      : 'Evening wrap off',
                );
              },
            ),
            if (state.eveningWrapEnabled) ...[
              const SettingsSubLabel('Time'),
              for (final t in eveningWrapTimes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SelectableTile(
                    title: clockLabel(t),
                    isSelected: state.eveningWrapTime == t,
                    onTap: () {
                      if (state.eveningWrapTime == t) return;
                      cubit.setEveningWrapTime(t);
                      settingsToast(context, 'Evening wrap at ${clockLabel(t)}');
                    },
                  ),
                ),
              if (_preview case final text?) ...[
                const SettingsSubLabel('What it looks like tonight'),
                _NotificationPreview(
                  title: text.title,
                  body: text.body,
                  time: clockLabel(state.eveningWrapTime),
                ),
              ],
              const SettingsNote(
                'If everyone has an answer, the wrap just says so.',
              ),
            ] else
              const SettingsNote(
                'With the wrap off, nothing is sent in the evening.',
              ),
          ],
        );
      },
    );
  }
}

class _NotificationPreview extends StatelessWidget {
  final String title;
  final String body;
  final String time;
  const _NotificationPreview({
    required this.title,
    required this.body,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.dividerColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const EchoMascot(state: EchoState.idle, size: 18),
              const SizedBox(width: 6),
              Text(
                'Echo · $time',
                style: GoogleFonts.nunito(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: c.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: GoogleFonts.nunito(
              fontSize: 15,
              height: 1.3,
              fontWeight: FontWeight.w800,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            body,
            style: GoogleFonts.nunito(
              fontSize: 13.5,
              height: 1.45,
              color: c.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
