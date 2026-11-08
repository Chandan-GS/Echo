import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/widgets/press_feedback.dart';
import 'package:project_echo/core/services/gemini_usage.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/data/context/addressed.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/people/presentation/widgets/people_parts.dart'
    show appLabel;
import 'package:project_echo/features/vault/presentation/widgets/source_icon.dart';

/// [text] with every occurrence of [words] marked. Matches ignore case.
List<TextSpan> highlightSpans(
  String text,
  List<String> words,
  TextStyle highlight,
) {
  if (words.isEmpty || text.isEmpty) return [TextSpan(text: text)];
  final pattern = RegExp(
    words.map(RegExp.escape).join('|'),
    caseSensitive: false,
    unicode: true,
  );
  final spans = <TextSpan>[];
  var from = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > from) {
      spans.add(TextSpan(text: text.substring(from, match.start)));
    }
    spans.add(TextSpan(text: match[0], style: highlight));
    from = match.end;
  }
  if (from < text.length) spans.add(TextSpan(text: text.substring(from)));
  return spans;
}

/// A small icon for an app, falling back to a plain circle.
class HistoryAppIcon extends StatelessWidget {
  final String source;
  final double size;
  const HistoryAppIcon({super.key, required this.source, this.size = 18});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * 0.28),
    child: SourceIcon(
      source: source,
      size: size,
      fallback: Icon(
        Symbols.notifications_rounded,
        size: size,
        color: context.colors.textSecondary,
      ),
    ),
  );
}

/// A little label beside a sender's name.
class HistoryTag extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color background;
  final Color foreground;

  const HistoryTag({
    super.key,
    required this.text,
    required this.background,
    required this.foreground,
    this.icon,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: foreground, fill: 1),
          const SizedBox(width: 4),
        ],
        Text(
          text,
          style: GoogleFonts.nunito(
            fontSize: 11.5,
            height: 1.2,
            fontWeight: FontWeight.w800,
            color: foreground,
          ),
        ),
      ],
    ),
  );
}

/// The labels a message has earned, in the order the design lists them.
List<Widget> historyTags(BuildContext context, RawData e) {
  final c = context.colors;
  final tint = c.dividerColor.withValues(alpha: 0.45);
  final addressed = Addressed.parse(e.addressed);
  final toYou = switch (addressed) {
    Addressed.direct => 'to you',
    Addressed.mentioned => 'mentions you',
    Addressed.reply => 'replying to you',
    _ => null,
  };
  return [
    if (toYou != null)
      HistoryTag(
        text: toYou,
        background: context.selectionFill,
        foreground: context.onSelection,
      ),
    if (e.heldAt != null)
      HistoryTag(
        text: 'held',
        icon: Symbols.bedtime_rounded,
        background: c.amberBackground,
        foreground: context.warmAccent,
      ),
    if (e.swipedAt != null)
      HistoryTag(
        text: 'swiped away',
        icon: Symbols.swipe_left_rounded,
        background: tint,
        foreground: c.textSecondary,
      ),
    if (e.sent == true)
      HistoryTag(
        text: 'you sent',
        icon: Symbols.north_east_rounded,
        background: tint,
        foreground: c.textSecondary,
      ),
  ];
}

/// One notification in the list.
class HistoryCard extends StatelessWidget {
  final RawData entry;
  final List<String> words;
  final VoidCallback onTap;

  const HistoryCard({
    super.key,
    required this.entry,
    required this.words,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mark = TextStyle(backgroundColor: c.amberBackground);
    final tags = historyTags(context, entry);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PressFeedback(
        scale: 0.985,
        haptic: false,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: c.dividerColor.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    HistoryAppIcon(source: entry.source),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: highlightSpans(appLabel(entry.source), words, mark),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.nunito(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: c.primaryGreen,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      clockTime(entry.timestamp),
                      style: GoogleFonts.nunito(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: highlightSpans(entry.who, words, mark),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.nunito(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                    ...tags,
                  ],
                ),
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(
                    children: highlightSpans(entry.content, words, mark),
                  ),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    height: 1.4,
                    color: c.textPrimary.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Today", "Yesterday", a weekday this past week, or a date before that.
String historyDayLabel(DateTime day, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  if (day == today) return 'Today';
  if (day == DateTime(now.year, now.month, now.day - 1)) return 'Yesterday';
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  if (!day.isBefore(DateTime(now.year, now.month, now.day - 6))) {
    return weekdays[day.weekday - 1];
  }
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${day.day} ${months[day.month - 1]}';
}
