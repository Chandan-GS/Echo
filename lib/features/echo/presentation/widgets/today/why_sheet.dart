import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/widgets/press_feedback.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/data/waiting/waiting_store.dart';
import 'package:project_echo/features/echo/presentation/widgets/today/today_parts.dart';

/// "Why is this person here?": the message, each thing Echo noticed, and the
/// two answers. True means no reply is needed; null, keep it.
Future<bool?> showWhySheet(BuildContext context, WaitingItem item) =>
    showTodaySheet<bool>(context, (_) => _WhySheet(item: item));

class _WhySheet extends StatelessWidget {
  final WaitingItem item;
  const _WhySheet({required this.item});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = item.message.sender;
    return TodaySheetBody(
      children: [
        Text('Why $name is here', style: todaySheetTitle(context)),
        const SizedBox(height: 4),
        Text(
          'Echo puts someone on this list only when a message is meant for '
          'you and asks something of you.',
          style: todaySheetSub(context),
        ),
        const SizedBox(height: 12),
        QuoteBox(who: name, text: item.message.content),
        const SizedBox(height: 4),
        for (final (i, signal) in item.reason.signals.indexed)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              border: i == item.reason.signals.length - 1
                  ? null
                  : Border(
                      bottom: BorderSide(
                        color: c.dividerColor.withValues(alpha: 0.6),
                      ),
                    ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    Symbols.check_circle_rounded,
                    fill: 1,
                    size: 20,
                    color: c.primaryGreen,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    signal,
                    style: GoogleFonts.nunito(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                      color: c.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 16),
          child: Text(
            'If $name had only said thanks, ok, or sent an emoji, Echo would '
            'have left it off the list.',
            style: GoogleFonts.nunito(
              fontSize: 12.5,
              height: 1.5,
              color: c.textSecondary,
            ),
          ),
        ),
        SheetBlockButton(
          label: 'No reply needed',
          ghost: true,
          onTap: () => Navigator.of(context).pop(true),
        ),
        const SizedBox(height: 10),
        SheetBlockButton(
          label: 'Keep it on my list',
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// A full-width button at the foot of a sheet.
class SheetBlockButton extends StatelessWidget {
  final String label;
  final bool ghost;
  final VoidCallback onTap;

  const SheetBlockButton({
    super.key,
    required this.label,
    required this.onTap,
    this.ghost = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PressFeedback(
      scale: 0.97,
      child: Material(
        color: ghost ? Colors.transparent : c.buttonDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: ghost
              ? BorderSide(color: c.dividerColor, width: 1.5)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 56,
            child: Center(
              child: Text(
                label,
                style: GoogleFonts.nunito(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: ghost ? c.textPrimary : c.textInverse,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
