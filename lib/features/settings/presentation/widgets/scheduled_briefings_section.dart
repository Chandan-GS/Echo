import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_state.dart';

class ScheduledBriefingsSection extends StatelessWidget {
  const ScheduledBriefingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        final times = state.briefingTimes;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your automated AI briefings will run in the background at these times.',
              style: TextStyle(
                fontSize: 14,
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ...times.map((time) {
                  return _buildTimeChip(context, time);
                }).toList(),
                _buildAddButton(context),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildTimeChip(BuildContext context, String time) {
    final parsedTime = _parseTime(time);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: context.colors.lightGreenBackground,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            parsedTime.format(context),
            style: GoogleFonts.nunito(
              fontWeight: FontWeight.bold,
              color: context.colors.textPrimary,
              fontSize: 16,
            ),
          ),
          const SizedBox(width: 16),
          GestureDetector(
            onTap: () {
              context.read<SettingsCubit>().removeBriefingTime(time);
            },
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(shape: BoxShape.circle),
              child: Icon(
                Icons.close_rounded,
                size: 20,
                color: context.colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddButton(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final time = await showTimePicker(
          context: context,
          initialTime: const TimeOfDay(hour: 7, minute: 0),
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                timePickerTheme: TimePickerThemeData(
                  backgroundColor: context.colors.background,
                  dialHandColor: context.colors.primaryGreen,
                  dayPeriodColor: WidgetStateColor.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? context.colors.primaryGreen.withOpacity(0.2)
                        : Colors.transparent,
                  ),
                  dayPeriodTextColor: Theme.of(context).colorScheme.onSecondary,
                ),
                colorScheme: ColorScheme.light(
                  primary: context.colors.primaryGreen,
                  onPrimary: Colors.white,
                  surface: context.colors.background,
                  onSurface: context.colors.textPrimary,
                ),
              ),
              child: child!,
            );
          },
        );

        if (time != null && context.mounted) {
          final timeStr =
              '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
          context.read<SettingsCubit>().addBriefingTime(timeStr);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: context.colors.textSecondary.withOpacity(0.5),
            style: BorderStyle.solid,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 20, color: context.colors.textSecondary),
            const SizedBox(width: 16),
            Text(
              'Add Time',
              style: GoogleFonts.nunito(
                fontWeight: FontWeight.w600,
                color: context.colors.textSecondary,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  TimeOfDay _parseTime(String time) {
    final parts = time.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }
}
