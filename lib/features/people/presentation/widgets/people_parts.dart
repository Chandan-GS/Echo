import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/widgets/press_feedback.dart';
import 'package:project_echo/core/services/reminders.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/people/data/person_tally.dart';
import 'package:project_echo/features/vault/presentation/widgets/source_icon.dart';

/// A section title in the page's serif, with a quiet note at its right.
class PeopleSection extends StatelessWidget {
  final String title;
  final String? note;

  const PeopleSection(this.title, {super.key, this.note});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.oldStandardTt(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                height: 1.1,
                color: c.textPrimary,
              ),
            ),
          ),
          if (note != null) ...[
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                note!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.nunito(fontSize: 13, color: c.textSecondary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A name with what's being searched for picked out.
class HighlightedName extends StatelessWidget {
  final String name;
  final String query;
  final TextStyle style;

  const HighlightedName(
    this.name, {
    super.key,
    required this.query,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    final at = query.isEmpty ? -1 : name.toLowerCase().indexOf(query);
    if (at < 0) {
      return Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: name.substring(0, at)),
          TextSpan(
            text: name.substring(at, at + query.length),
            style: TextStyle(backgroundColor: context.colors.amberBackground),
          ),
          TextSpan(text: name.substring(at + query.length)),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Rust, for what has waited a long time.
const _rust = Color(0xFFB4532A);

/// A small tag, tinted by how long something has waited.
class AgeTag extends StatelessWidget {
  final String text;

  /// 0 green, 1 amber, 2 rust; null plain.
  final int? age;
  final IconData? icon;

  const AgeTag(this.text, {super.key, this.age, this.icon});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (bg, fg) = switch (age) {
      0 => (context.selectionFill, context.onSelection),
      1 => (c.amberBackground, context.warmAccent),
      2 => (
        _rust.withValues(alpha: 0.14),
        context.isDarkMode ? const Color(0xFFE29A77) : _rust,
      ),
      _ => (c.dividerColor.withValues(alpha: 0.45), c.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.nunito(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The small icons of the apps someone writes on.
class AppIcons extends StatelessWidget {
  final List<String> sources;
  final double size;

  const AppIcons(this.sources, {super.key, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final s in sources.take(3))
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(size / 4),
              child: SourceIcon(
                source: s,
                size: size,
                fallback: SizedBox(width: size, height: size),
              ),
            ),
          ),
      ],
    );
  }
}

/// Messages per week, as thin bars. The last [low] are the quiet ones.
class WeekBars extends StatelessWidget {
  final List<int> bars;
  final int low;

  const WeekBars({super.key, required this.bars, required this.low});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final top = bars.fold<int>(1, (a, b) => b > a ? b : a);
    return Semantics(
      label: 'Messages per week',
      child: SizedBox(
        height: 28,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final (i, v) in bars.indexed)
              Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : 3),
                child: Container(
                  width: 4,
                  height: (v / top * 24).clamp(2, 24).toDouble(),
                  decoration: BoxDecoration(
                    color: i >= bars.length - low
                        ? context.warmAccent
                        : c.textPrimary.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A tappable row inside a card, sinking a little under the finger.
class PeopleRow extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool first;

  const PeopleRow({
    super.key,
    required this.child,
    this.onTap,
    this.first = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PressFeedback(
      scale: 0.985,
      enabled: onTap != null,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: first
              ? null
              : BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: c.dividerColor.withValues(alpha: 0.6),
                    ),
                  ),
                ),
          child: child,
        ),
      ),
    );
  }
}

/// The app's pill button, with a label that ellipsizes instead of pushing
/// off a narrow phone or at a large text size.
class PeoplePill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool filled;
  final bool set;
  final VoidCallback? onTap;

  const PeoplePill({
    super.key,
    required this.label,
    this.icon,
    this.filled = false,
    this.set = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = set
        ? context.onSelection
        : filled
        ? c.background
        : c.textPrimary;
    return PressFeedback(
      enabled: onTap != null,
      child: Material(
        color: set
            ? context.selectionFill
            : filled
            ? c.textPrimary
            : Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(
            color: set
                ? Colors.transparent
                : filled
                ? c.textPrimary
                : c.textPrimary.withValues(alpha: 0.35),
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
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.nunito(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: fg,
                    ),
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

/// A short message floating above the dock.
void showPeopleSnack(BuildContext context, String text) {
  final bottom = MediaQuery.paddingOf(context).bottom;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.fromLTRB(20, 0, 20, bottom),
      content: Text(text),
    ),
  );
}

/// Apps by the name people know them by.
String appLabel(String source) {
  final s = source.trim().toLowerCase();
  return switch (s) {
    'whatsapp' => 'WhatsApp',
    'whatsapp business' => 'WhatsApp Business',
    'telegram' => 'Telegram',
    'slack' => 'Slack',
    'teams' || 'microsoft teams' => 'Teams',
    'instagram' => 'Instagram',
    'messenger' => 'Messenger',
    'discord' => 'Discord',
    'signal' => 'Signal',
    'messages' => 'Messages',
    'gmail' => 'Gmail',
    'github' => 'GitHub',
    'linkedin' => 'LinkedIn',
    'youtube' => 'YouTube',
    'googlequicksearchbox' => 'Google',
    'vending' => 'Play Store',
    _ => source.isEmpty ? source : '${source[0].toUpperCase()}${source.substring(1)}',
  };
}

/// A pill's label with [name] when it fits, or just [action] for a long one:
/// a pill can't wrap, and a long name mustn't push it off a narrow phone.
String pillWith(String action, String name) =>
    name.runes.length <= 10 ? '$action $name' : action;

/// "WhatsApp and Slack".
String appNames(List<String> sources) {
  final names = sources.map(appLabel).toList();
  if (names.length < 2) return names.join();
  return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
}

/// When "Remind me at 9" means, from [now]: this morning at 9 until then,
/// then this evening at 9. Null once it's past 9 at night.
DateTime? nextNine(DateTime now) {
  final morning = DateTime(now.year, now.month, now.day, 9);
  if (now.isBefore(morning)) return morning;
  final evening = DateTime(now.year, now.month, now.day, 21);
  return now.isBefore(evening) ? evening : null;
}

/// Sets a reminder or takes it off again.
Future<bool> toggleReminder({
  required String key,
  required DateTime at,
  required String title,
  required String body,
  String? thread,
}) async {
  if (await Reminders.setFor(key) != null) {
    await Reminders.cancel(key);
    return false;
  }
  await Reminders.set(
    message: key,
    at: at,
    title: title,
    body: body,
    thread: thread,
  );
  return true;
}

/// The day label on a reminder pill: "Thu", or "tomorrow".
String shortDay(DateTime d, DateTime now) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final diff = dayOf(d) - dayOf(now);
  if (diff == 0) return 'today';
  if (diff == 1) return 'tomorrow';
  return days[d.weekday - 1];
}

/// The right edge of a row: a chevron.
class RowChevron extends StatelessWidget {
  const RowChevron({super.key});

  @override
  Widget build(BuildContext context) => Icon(
    Symbols.chevron_right_rounded,
    size: 20,
    color: context.colors.textSecondary,
  );
}
