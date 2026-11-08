import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/presentation/widgets/press_feedback.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';

/// "ECHO", over a group of rows.
class SettingsGroupLabel extends StatelessWidget {
  final String text;
  final bool first;
  const SettingsGroupLabel(this.text, {super.key, this.first = false});

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(6, first ? 8 : 26, 6, 10),
    child: Text(
      text.toUpperCase(),
      style: GoogleFonts.nunito(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.5,
        color: context.colors.textSecondary,
      ),
    ),
  );
}

/// Rows in one rounded card, divided by hairlines.
class SettingsGroup extends StatelessWidget {
  final List<Widget> rows;
  final double dividerIndent;
  const SettingsGroup({super.key, required this.rows, this.dividerIndent = 64});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.dividerColor.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, row) in rows.indexed) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: dividerIndent,
                color: c.dividerColor.withValues(alpha: 0.6),
              ),
            row,
          ],
        ],
      ),
    );
  }
}

/// A setting: its icon, its name, its current value, and what's at the end
/// of the row (a chevron unless [trailing] says otherwise).
class SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? value;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool hideChevron;
  final bool danger;

  /// The value wraps instead of stopping at one line.
  final bool tall;

  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
    this.trailing,
    this.hideChevron = false,
    this.danger = false,
    this.tall = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = danger ? context.warmAccent : c.textPrimary;
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(14, 13, 10, 13),
      child: Row(
        crossAxisAlignment: tall
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Color.lerp(c.background, c.surface, 0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 19, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.nunito(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
                if (value != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    value!,
                    maxLines: tall ? null : 1,
                    overflow: tall ? null : TextOverflow.ellipsis,
                    style: GoogleFonts.nunito(
                      fontSize: 12.5,
                      height: tall ? 1.45 : null,
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
          if (trailing == null && !hideChevron)
            Icon(
              Symbols.chevron_right_rounded,
              size: 22,
              color: c.textSecondary.withValues(alpha: 0.7),
            ),
        ],
      ),
    );
    if (onTap == null) return row;
    return PressFeedback(
      scale: 0.98,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(onTap: onTap, child: row),
      ),
    );
  }
}

/// A setting that's just on or off, with the icon in a circle like the
/// other rows of its group.
class SettingsSwitchRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final bool on;
  final ValueChanged<bool> onChanged;
  final bool tall;

  const SettingsSwitchRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.on,
    required this.onChanged,
    this.tall = false,
  });

  @override
  Widget build(BuildContext context) => SettingsRow(
    icon: icon,
    title: title,
    value: value,
    tall: tall,
    onTap: () => onChanged(!on),
    trailing: Switch(
      value: on,
      activeTrackColor: context.colors.primaryGreen,
      onChanged: onChanged,
    ),
  );
}

/// The switch at the top of a sub-page: a green icon, no circle.
class SettingsSwitchCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final bool on;
  final ValueChanged<bool> onChanged;

  const SettingsSwitchCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.on,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.dividerColor.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => onChanged(!on),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              children: [
                Icon(icon, fill: 1, size: 24, color: c.primaryGreen),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.nunito(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        value,
                        style: GoogleFonts.nunito(
                          fontSize: 12.5,
                          height: 1.4,
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Switch(
                  value: on,
                  activeTrackColor: c.primaryGreen,
                  onChanged: onChanged,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small heading inside a sub-page ("TIME", "WITHOUT THE PACK").
class SettingsSubLabel extends StatelessWidget {
  final String text;
  const SettingsSubLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 24, 6, 10),
    child: Text(
      text.toUpperCase(),
      style: GoogleFonts.nunito(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.6,
        color: context.colors.textSecondary,
      ),
    ),
  );
}

/// A quiet line of explanation under a control.
class SettingsNote extends StatelessWidget {
  final String text;
  const SettingsNote(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 14, 6, 0),
    child: Text(
      text,
      style: GoogleFonts.nunito(
        fontSize: 13,
        height: 1.5,
        color: context.colors.textSecondary,
      ),
    ),
  );
}

/// A tinted card that says how things stand, and sometimes leads somewhere.
class SettingsHint extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback? onTap;

  const SettingsHint({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fill = context.isDarkMode
        ? Color.lerp(c.surface, c.primaryGreen, 0.16)!
        : Color.lerp(c.surface, context.selectionFill, 0.55)!;
    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, fill: 1, size: 22, color: c.primaryGreen),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.nunito(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      body,
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        height: 1.45,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks before something that can't be undone. True when confirmed.
Future<bool> confirmSettingsAction(
  BuildContext context, {
  required String title,
  required String body,
  required String confirm,
  bool danger = true,
}) async {
  final confirmed = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    transitionDuration: AppMotion.fast,
    transitionBuilder: (context, animation, _, child) => Transform.scale(
      scale: Curves.easeOutBack.transform(animation.value),
      child: child,
    ),
    pageBuilder: (context, _, _) {
      final c = context.colors;
      return SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Material(
              color: c.surface,
              borderRadius: BorderRadius.circular(24),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 22, 14, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        title,
                        style: GoogleFonts.nunito(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        body,
                        style: GoogleFonts.nunito(
                          fontSize: 14,
                          height: 1.5,
                          color: c.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.nunito(
                              fontWeight: FontWeight.w700,
                              color: c.textSecondary,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: Text(
                            confirm,
                            style: GoogleFonts.nunito(
                              fontWeight: FontWeight.w800,
                              color: danger
                                  ? context.warmAccent
                                  : c.primaryGreen,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
  return confirmed ?? false;
}

/// A short message at the bottom of the screen, replacing any before it.
void settingsToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
