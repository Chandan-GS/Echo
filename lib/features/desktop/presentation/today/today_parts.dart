import 'package:flutter/material.dart';
import 'package:project_echo/core/presentation/widgets/press_feedback.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';

/// The pieces the Today screen's three columns share.

extension TodayColors on BuildContext {
  /// A selected row: the selection green, toned down in dark mode so the
  /// row's text and its green bar still read.
  Color get rowSelected => isDarkMode
      ? Color.alphaBlend(
          colors.primaryGreen.withValues(alpha: 0.22),
          colors.background,
        )
      : selectionFill;

  /// Text on [rowSelected].
  Color get onRowSelected => isDarkMode ? colors.textPrimary : onSelection;

  /// Text that matters least: times under a message.
  Color get faint => colors.textSecondary.withValues(alpha: 0.75);
}

enum DeskButtonStyle { outlined, filled, green, set }

/// The desktop's stadium button: outlined, [DeskButtonStyle.filled] dark,
/// green for the one that sends, or [DeskButtonStyle.set] for something
/// already on. [keyHint] shows its shortcut after the label.
class DeskButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final String? keyHint;
  final DeskButtonStyle style;
  final VoidCallback? onTap;

  const DeskButton({
    super.key,
    required this.label,
    this.icon,
    this.keyHint,
    this.style = DeskButtonStyle.outlined,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (bg, fg, border) = switch (style) {
      DeskButtonStyle.outlined => (
        Colors.transparent,
        c.textPrimary,
        c.textPrimary.withValues(alpha: 0.25),
      ),
      DeskButtonStyle.filled => (c.textPrimary, c.background, c.textPrimary),
      DeskButtonStyle.green => (
        c.primaryGreen,
        context.isDarkMode ? context.onSelection : Colors.white,
        c.primaryGreen,
      ),
      DeskButtonStyle.set => (
        context.selectionFill,
        context.onSelection,
        Colors.transparent,
      ),
    };
    return PressFeedback(
      haptic: false,
      enabled: onTap != null,
      child: Material(
        color: bg,
        shape: StadiumBorder(side: BorderSide(color: border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 18,
                    fill: style == DeskButtonStyle.set ? 1 : 0,
                    color: fg,
                  ),
                  const SizedBox(width: 7),
                ],
                Text(
                  label,
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
                if (keyHint != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    keyHint!,
                    style: GoogleFonts.nunito(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: fg.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A square icon button with a tooltip, for a header.
class DeskIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  const DeskIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: PressFeedback(
      haptic: false,
      enabled: onTap != null,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, size: 20, color: context.colors.textSecondary),
          ),
        ),
      ),
    ),
  );
}

/// "WAITING ON YOU", small and spaced, with an optional note on the right.
class PanelLabel extends StatelessWidget {
  final String text;
  final String? trailing;
  final EdgeInsetsGeometry padding;
  const PanelLabel(
    this.text, {
    super.key,
    this.trailing,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.nunito(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.3,
      color: context.colors.textSecondary,
    );
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Text(text.toUpperCase(), style: style),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              trailing ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: style.copyWith(
                letterSpacing: 0,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
