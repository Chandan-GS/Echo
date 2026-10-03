import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/widgets/press_feedback.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/desktop/presentation/vault/vault_filter.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/ask_parts.dart';

/// The pieces of the desktop Vault's table: filter chips, the column
/// headings, a day's heading, an entry's row and the detail panel.

/// Column widths; the message takes what's left.
const vaultTimeWidth = 92.0;
const vaultFromWidth = 250.0;
const vaultTagWidth = 150.0;

/// A filter: outlined, or dark when it's on. [leading] is an app's icon.
class VaultChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Widget? leading;
  final IconData? trailingIcon;
  final VoidCallback? onTap;
  const VaultChip({
    super.key,
    required this.label,
    required this.selected,
    this.leading,
    this.trailingIcon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = selected ? c.background : c.textSecondary;
    final look = Material(
      color: selected ? c.textPrimary : c.surface,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? c.textPrimary : c.dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(leading != null ? 8 : 12, 7, 12, 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 7)],
              Text(
                label,
                style: GoogleFonts.nunito(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: 3),
                Icon(trailingIcon, size: 16, color: fg),
              ],
            ],
          ),
        ),
      ),
    );
    return onTap == null ? look : PressFeedback(child: look);
  }
}

/// The thin rule between groups of chips.
class VaultChipDivider extends StatelessWidget {
  const VaultChipDivider({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 22,
    margin: const EdgeInsets.symmetric(horizontal: 4),
    color: context.colors.dividerColor,
  );
}

/// "Time · From · Message", above the scrolling rows so it stays put.
class VaultColumnHeadings extends StatelessWidget {
  const VaultColumnHeadings({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = GoogleFonts.nunito(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.3,
      color: c.textSecondary,
    );
    Widget cell(String label) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Text(label, style: style),
    );
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.dividerColor)),
      ),
      child: Row(
        children: [
          SizedBox(width: vaultTimeWidth, child: cell('TIME')),
          SizedBox(width: vaultFromWidth, child: cell('FROM')),
          Expanded(child: cell('MESSAGE')),
          const SizedBox(width: vaultTagWidth),
        ],
      ),
    );
  }
}

/// "Today · 117 signals", starting a day's rows.
class VaultDayRow extends StatelessWidget {
  final VaultDayLine line;
  final DateTime now;
  const VaultDayRow(this.line, {super.key, required this.now});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 20, 10, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.dividerColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              vaultDayLabel(line.day, now),
              style: GoogleFonts.oldStandardTt(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
          ),
          Text(
            '${groupedCount(line.count)} signal${line.count == 1 ? '' : 's'}',
            style: GoogleFonts.nunito(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: c.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// One entry: time, app and who, the message, and whether it was for the
/// owner. Lights up under the mouse; [selected] while its detail is open.
class VaultEntryRow extends StatelessWidget {
  final VaultItem item;
  final bool selected;
  final VoidCallback onTap;
  const VaultEntryRow({
    super.key,
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final entry = item.entry;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.dividerColor)),
      ),
      child: Material(
        color: selected
            ? c.primaryGreen.withValues(alpha: 0.12)
            : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          hoverColor: c.textPrimary.withValues(alpha: 0.04),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 11),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: vaultTimeWidth,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 1, 10, 0),
                        child: Text(
                          clockLabel(entry.timestamp),
                          style: GoogleFonts.nunito(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: c.textSecondary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: vaultFromWidth, child: _From(item)),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          entry.content,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.nunito(
                            fontSize: 13.5,
                            height: 1.45,
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: vaultTagWidth,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: item.forYou == null
                              ? null
                              : ForYouTag(item.forYou!),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Positioned(
                  left: 0,
                  top: 10,
                  bottom: 10,
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: c.primaryGreen,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The app's icon, then who in bold over the group or app.
class _From extends StatelessWidget {
  final VaultItem item;
  const _From(this.item);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SourceBadge(item.entry, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.who,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.nunito(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
                Text(
                  item.where,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.nunito(
                    fontSize: 12,
                    color: c.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A calm line in place of rows: no match, or nothing synced yet.
class VaultNote extends StatelessWidget {
  final String text;
  const VaultNote(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 28),
    child: Text(
      text,
      style: GoogleFonts.nunito(
        fontSize: 13.5,
        color: context.colors.textSecondary,
      ),
    ),
  );
}

/// The whole of one entry, beside the table: who and when, the full
/// message (selectable, to copy from), and what to do with it.
class VaultDetailPanel extends StatelessWidget {
  final VaultItem item;
  final DateTime now;
  final VoidCallback onClose;
  final VoidCallback? onAsk;
  final VoidCallback onOpenOnPhone;
  const VaultDetailPanel({
    super.key,
    required this.item,
    required this.now,
    required this.onClose,
    required this.onAsk,
    required this.onOpenOnPhone,
  });

  static const width = 380.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final RawData entry = item.entry;
    final t = entry.timestamp;
    final where = item.where == item.app
        ? item.app
        : '${item.where} · ${item.app}';
    return Container(
      width: width,
      height: double.infinity,
      decoration: BoxDecoration(
        color: c.background,
        border: Border(left: BorderSide(color: c.dividerColor)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: SourceBadge(entry, size: 36),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.who,
                          style: GoogleFonts.nunito(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: c.textPrimary,
                          ),
                        ),
                        Text(
                          where,
                          style: GoogleFonts.nunito(
                            fontSize: 12.5,
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  tooltip: 'Close',
                  icon: Icon(
                    Symbols.close_rounded,
                    size: 20,
                    color: c.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  '${vaultDayLabel(t, now)} at ${clockLabel(t)}',
                  style: GoogleFonts.nunito(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: c.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (item.forYou != null) ...[
                  const SizedBox(width: 10),
                  ForYouTag(item.forYou!),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: c.dividerColor),
              ),
              child: SelectableText(
                entry.content,
                style: GoogleFonts.nunito(
                  fontSize: 15,
                  height: 1.5,
                  color: c.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onAsk != null)
                  AskPill(
                    label: 'Ask about this',
                    icon: Symbols.forum_rounded,
                    filled: true,
                    onTap: onAsk,
                  ),
                AskPill(
                  label: 'Open on phone',
                  icon: Symbols.open_in_new_rounded,
                  onTap: onOpenOnPhone,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
