import 'package:flutter/material.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';

/// A solid, borderless selection row used across onboarding (voices, tone, …).
///
/// Selection is shown by a full tonal fill (no borders, no translucency): the
/// selected row is a solid green-tinted container with a filled check; the
/// unselected row is a solid neutral surface. A real [InkWell] gives the M3
/// ripple on press.
class SelectableTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool isSelected;
  final VoidCallback onTap;
  final Widget? leading;
  final Widget? trailing;
  final bool showCheck;

  const SelectableTile({
    super.key,
    required this.title,
    required this.isSelected,
    required this.onTap,
    this.subtitle,
    this.leading,
    this.trailing,
    this.showCheck = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = BorderRadius.circular(20);
    final onSel = context.onSelection;

    return AnimatedContainer(
      duration: AppMotion.medium,
      curve: AppMotion.emphasized,
      decoration: BoxDecoration(
        color: isSelected ? context.selectionFill : colors.surface,
        borderRadius: radius,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            child: Row(
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.nunito(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: isSelected ? onSel : colors.textPrimary,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          style: GoogleFonts.nunito(
                            fontSize: 13,
                            height: 1.3,
                            color: isSelected
                                ? onSel.withValues(alpha: 0.7)
                                : colors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null)
                  trailing!
                else if (showCheck)
                  _CheckDisc(isSelected: isSelected),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A filled check that springs in on selection. When selected it's a dark disc
/// (matching [onSelection]) with a light tick, so it stays crisp on the green
/// tile; unselected it's a quiet neutral dot.
class _CheckDisc extends StatelessWidget {
  final bool isSelected;
  const _CheckDisc({required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AnimatedContainer(
      duration: AppMotion.fast,
      curve: AppMotion.spring,
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSelected ? context.onSelection : colors.dividerColor,
      ),
      child: AnimatedScale(
        scale: isSelected ? 1.0 : 0.0,
        duration: AppMotion.fast,
        curve: AppMotion.spring,
        child: Icon(Icons.check_rounded, size: 17, color: context.selectionFill),
      ),
    );
  }
}
