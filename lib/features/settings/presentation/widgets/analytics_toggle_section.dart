import 'package:flutter/material.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/core/services/analytics_service.dart';
import 'package:project_echo/core/theme/app_theme.dart';

/// A single opt-out switch for anonymous usage analytics. Enabled by default;
/// flipping it off stops all event tracking immediately (see [Analytics]).
class AnalyticsToggleSection extends StatefulWidget {
  const AnalyticsToggleSection({super.key});

  @override
  State<AnalyticsToggleSection> createState() => _AnalyticsToggleSectionState();
}

class _AnalyticsToggleSectionState extends State<AnalyticsToggleSection> {
  late bool _enabled = Analytics.isEnabled;

  Future<void> _onChanged(bool value) async {
    await Analytics.setEnabled(value);
    if (mounted) setState(() => _enabled = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.dividerColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Share anonymous usage data',
                  style: GoogleFonts.nunito(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Helps improve Echo. Counts which features are used — never your '
                  'notifications, messages, or briefings. No account, no personal data.',
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    height: 1.4,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: _enabled,
            activeTrackColor: colors.primaryGreen,
            onChanged: _onChanged,
          ),
        ],
      ),
    );
  }
}
