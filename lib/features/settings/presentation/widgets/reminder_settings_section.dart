import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/widgets/echo_segmented.dart';
import 'package:project_echo/core/services/reminder_settings.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';

/// Settings → Reminders: how long before a time Echo suggests reminding,
/// and whether it suggests at all.
class ReminderSettingsSection extends StatelessWidget {
  const ReminderSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: Listenable.merge([
        ReminderSettings.lead,
        ReminderSettings.suggest,
      ]),
      builder: (context, _) {
        final lead = ReminderSettings.lead.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EchoSegmented(
              labels: const ['10 min', '20 min', '30 min', '1 hour'],
              selected: ReminderSettings.leads.indexOf(lead).clamp(0, 3),
              onSelect: (i) =>
                  ReminderSettings.setLead(ReminderSettings.leads[i]),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: c.dividerColor.withValues(alpha: 0.5),
                ),
              ),
              child: SwitchListTile(
                value: ReminderSettings.suggest.value,
                onChanged: ReminderSettings.setSuggest,
                contentPadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
                secondary: Icon(
                  Symbols.auto_awesome_rounded,
                  color: c.primaryGreen,
                ),
                title: Text(
                  'Echo suggests reminders',
                  style: GoogleFonts.nunito(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ),
                subtitle: Text(
                  'On to-dos that name a time',
                  style: GoogleFonts.nunito(
                    fontSize: 12.5,
                    color: c.textSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Android may deliver a reminder up to ten minutes after its '
              'time, so Echo’s suggestions leave room for that.',
              style: GoogleFonts.nunito(
                fontSize: 13,
                height: 1.5,
                color: c.textSecondary,
              ),
            ),
          ],
        );
      },
    );
  }
}
