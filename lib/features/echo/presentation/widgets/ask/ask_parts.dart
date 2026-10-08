import 'package:flutter/material.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/data/context/addressed.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/reply/reply_sender.dart';
import 'package:project_echo/features/todo/data/todo_item.dart';
import 'package:project_echo/features/vault/presentation/widgets/source_icon.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/widgets/press_feedback.dart';

/// The small pieces Ask Echo is built from, each matching a piece the app
/// already has (the to-do card's surface and rows, the limit card's pill
/// buttons, the thinking pill's green).

/// The to-do card's surface: white (dark grey), rounded, a hairline border.
class AskCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const AskCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 14),
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.dividerColor.withValues(alpha: 0.5)),
        boxShadow: context.isDarkMode
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: child,
    );
  }
}

/// A stadium button: [filled] dark (light in dark mode), outlined, or
/// [set]: soft green with a filled icon, for something already on ("Reminding
/// at 7:40 PM").
class AskPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool filled;
  final bool set;
  final VoidCallback? onTap;
  const AskPill({
    super.key,
    required this.label,
    this.icon,
    this.filled = false,
    this.set = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = set
        ? context.onSelection
        : filled
        ? colors.background
        : colors.textPrimary;
    return PressFeedback(
      enabled: onTap != null,
      child: Material(
        color: set
            ? context.selectionFill
            : filled
            ? colors.textPrimary
            : Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(
            color: set
                ? Colors.transparent
                : filled
                ? colors.textPrimary
                : colors.textPrimary.withValues(alpha: 0.35),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 17, fill: set ? 1 : 0, color: fg),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: GoogleFonts.nunito(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: fg,
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

/// The to-do card's solid button ("Make a to-do list").
class AskSolidButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  const AskSolidButton({
    super.key,
    required this.label,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return PressFeedback(
      enabled: onTap != null,
      child: Material(
        color: colors.textPrimary,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: colors.textInverse),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: GoogleFonts.nunito(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: colors.textInverse,
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

/// "to you", "mentions you", "replying to you", in the thinking pill's green.
class ForYouTag extends StatelessWidget {
  final Addressed addressed;
  const ForYouTag(this.addressed, {super.key});

  static String label(Addressed a) => switch (a) {
    Addressed.mentioned => 'mentions you',
    Addressed.reply => 'replying to you',
    _ => 'to you',
  };

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: context.selectionFill,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label(addressed),
      style: GoogleFonts.nunito(
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
        color: context.onSelection,
      ),
    ),
  );
}

/// A source number in an answer, as a small green dot: "1".
class CiteDot extends StatelessWidget {
  final int number;
  final VoidCallback? onTap;
  const CiteDot(this.number, {super.key, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 17,
      height: 17,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.selectionFill,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$number',
        style: GoogleFonts.nunito(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: context.onSelection,
          height: 1,
        ),
      ),
    ),
  );
}

/// The app a notification came from: its real icon when known.
class SourceBadge extends StatelessWidget {
  final RawData entry;
  final double size;
  const SourceBadge(this.entry, {super.key, this.size = 24});

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.colors.background,
        shape: BoxShape.circle,
      ),
      child: Icon(
        _fallbackIcon(entry.source),
        size: size / 2,
        color: context.colors.textSecondary,
      ),
    );
    final app = packageOfThread(entry.thread);
    return app != null
        ? SourceIcon.app(packageName: app, size: size, fallback: fallback)
        : SourceIcon(source: entry.source, size: size, fallback: fallback);
  }

  static IconData _fallbackIcon(String source) {
    final s = source.toLowerCase();
    if (s.contains('slack')) return Symbols.chat_bubble_rounded;
    if (s.contains('whatsapp')) return Symbols.message_rounded;
    if (s.contains('sms')) return Symbols.sms_rounded;
    if (s.contains('calendar')) return Symbols.calendar_today_rounded;
    if (s.contains('mail') || s.contains('gmail')) {
      return Symbols.mail_rounded;
    }
    return Symbols.notifications_rounded;
  }
}

/// A to-do as it reads on Home: the round check, the title, and its time in
/// green before who it came from.
class TodoLine extends StatelessWidget {
  final TodoItem item;
  final bool first;
  const TodoLine(this.item, {super.key, this.first = false});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final from = [
      item.sender,
      item.app,
    ].where((s) => s.trim().isNotEmpty).join(', ');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
      decoration: BoxDecoration(
        border: first
            ? null
            : Border(
                top: BorderSide(
                  color: colors.dividerColor.withValues(alpha: 0.6),
                ),
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: colors.primaryGreen.withValues(alpha: 0.55),
                width: 2,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: GoogleFonts.nunito(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: item.time ?? 'Anytime',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: colors.primaryGreen,
                        ),
                      ),
                      if (from.isNotEmpty) TextSpan(text: ' · $from'),
                    ],
                  ),
                  style: GoogleFonts.nunito(
                    fontSize: 12.5,
                    color: colors.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
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

/// "Rahul · College gang" in bold-then-plain, for a card's header line.
class WhoLine extends StatelessWidget {
  final RawData entry;
  final String? trailing;

  /// Whether to name the group a message was in.
  final bool showChat;
  const WhoLine(this.entry, {super.key, this.trailing, this.showChat = true});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final group =
        showChat && entry.isGroup && (entry.threadTitle?.isNotEmpty ?? false);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: entry.sender.isEmpty ? entry.source : entry.sender,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: colors.textPrimary,
            ),
          ),
          if (group) TextSpan(text: ' · ${entry.threadTitle}'),
          if (trailing != null) TextSpan(text: ' · $trailing'),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.nunito(fontSize: 12.5, color: colors.textSecondary),
    );
  }
}

/// "7:43 PM".
String clockLabel(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// When [t] is, from [now]: "at 7:40 PM" today, "tomorrow at 9:40 AM", "Mon
/// at 9 AM" within the week, "on 12 Oct at 9:40 AM" beyond.
String whenLabel(DateTime t, DateTime now) {
  final days = DateTime(
    t.year,
    t.month,
    t.day,
  ).difference(DateTime(now.year, now.month, now.day)).inDays;
  final at = 'at ${clockLabel(t)}';
  if (days == 0) return at;
  if (days == 1) return 'tomorrow $at';
  const week = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  if (days > 1 && days < 7) return '${week[t.weekday - 1]} $at';
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
  return 'on ${t.day} ${months[t.month - 1]} $at';
}

/// The emoji a reply can be, in one tap.
const quickReactions = ['👍', '❤️', '😂', '🙏'];

/// [quickReactions] as round buttons; [onPick] gets the one tapped.
class QuickReactions extends StatelessWidget {
  final ValueChanged<String> onPick;
  const QuickReactions({super.key, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, emoji) in quickReactions.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Semantics(
            button: true,
            label: 'Send $emoji',
            child: PressFeedback(
              scale: 0.85,
              child: Material(
                color: c.surface,
                shape: CircleBorder(side: BorderSide(color: c.dividerColor)),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onPick(emoji),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Center(
                      child: Text(emoji, style: const TextStyle(fontSize: 19)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
