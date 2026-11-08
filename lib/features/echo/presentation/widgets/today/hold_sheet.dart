import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/widgets/press_feedback.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/data/waiting/waiting_store.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/ask_parts.dart';
import 'package:project_echo/features/echo/presentation/widgets/today/today_parts.dart';
import 'package:project_echo/features/onboarding/data/onboarding_personalization.dart';
import 'package:project_echo/features/settings/data/tone_voice.dart';

/// What the owner chose in the hold sheet.
class HoldChoice {
  final String text;
  final DateTime? remindAt;
  const HoldChoice(this.text, this.remindAt);
}

/// When to bring a held reply back: 9 PM tonight, or tomorrow morning when
/// the evening is already over.
DateTime holdReminderFor(DateTime now) {
  final tonight = DateTime(now.year, now.month, now.day, 21);
  if (now.isBefore(tonight.subtract(const Duration(minutes: 30)))) {
    return tonight;
  }
  return DateTime(now.year, now.month, now.day + 1, 9);
}

/// A quick note so nobody's left on read.
Future<HoldChoice?> showHoldSheet(BuildContext context, WaitingItem item) =>
    showTodaySheet<HoldChoice>(context, (_) => _HoldSheet(item: item));

class _HoldSheet extends StatefulWidget {
  final WaitingItem item;
  const _HoldSheet({required this.item});

  @override
  State<_HoldSheet> createState() => _HoldSheetState();
}

class _HoldSheetState extends State<_HoldSheet> {
  /// In the owner's tone (Settings → Tone), once that's been read.
  List<String> _options = holdingReplies(OnboardingTone.friendly);

  @override
  void initState() {
    super.initState();
    currentTone().then((tone) {
      if (mounted) setState(() => _options = holdingReplies(tone));
    });
  }

  int _picked = 0;
  bool _remind = true;
  late final DateTime _at = holdReminderFor(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = widget.item.message.sender;
    final tonight = _at.day == DateTime.now().day;
    return TodaySheetBody(
      children: [
        Text('Hold for $name', style: todaySheetTitle(context)),
        const SizedBox(height: 4),
        Text(
          'A quick note so $name isn’t left on read. They stay on your list '
          'until you really reply.',
          style: todaySheetSub(context),
        ),
        const SizedBox(height: 16),
        for (final (i, option) in _options.indexed) ...[
          if (i > 0) const SizedBox(height: 8),
          _Option(
            icon: i == 0
                ? Symbols.auto_awesome_rounded
                : Symbols.chat_bubble_rounded,
            title: option,
            subtitle: i == 0 ? 'Echo suggests this one for $name' : null,
            on: _picked == i,
            onTap: () => setState(() => _picked = i),
          ),
        ],
        const SizedBox(height: 14),
        _RemindRow(
          on: _remind,
          title: tonight
              ? 'Remind me to reply at 9 PM'
              : 'Remind me tomorrow at 9 AM',
          subtitle: tonight
              ? 'Right after your evening wrap'
              : 'First thing in the morning',
          onTap: () => setState(() => _remind = !_remind),
        ),
        const SizedBox(height: 16),
        PressFeedback(
          scale: 0.97,
          child: Material(
            color: c.textPrimary,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.of(
                context,
              ).pop(HoldChoice(_options[_picked], _remind ? _at : null)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 13),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Symbols.schedule_send_rounded,
                      size: 20,
                      color: c.textInverse,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Send holding reply',
                      style: GoogleFonts.nunito(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: c.textInverse,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool on;
  final VoidCallback onTap;

  const _Option({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.on,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: on
              ? Color.lerp(c.surface, context.selectionFill, 0.3)
              : c.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            width: 1.5,
            color: on ? c.primaryGreen : c.dividerColor.withValues(alpha: 0.6),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: on && subtitle != null ? c.primaryGreen : c.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.nunito(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                      color: c.textPrimary,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: GoogleFonts.nunito(
                        fontSize: 12.5,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  width: 2,
                  color: on
                      ? c.primaryGreen
                      : c.textSecondary.withValues(alpha: 0.6),
                ),
              ),
              alignment: Alignment.center,
              child: AnimatedScale(
                duration: const Duration(milliseconds: 220),
                scale: on ? 1 : 0,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: c.primaryGreen,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RemindRow extends StatelessWidget {
  final bool on;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _RemindRow({
    required this.on,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      toggled: on,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              width: 1.5,
              color: c.dividerColor.withValues(alpha: 0.6),
            ),
          ),
          child: Row(
            children: [
              Icon(Symbols.alarm_rounded, size: 22, color: c.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.nunito(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.nunito(
                        fontSize: 12.5,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IgnorePointer(
                child: Switch(value: on, onChanged: (_) {}),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// How a held reply went, in the words of the toast.
String holdToast(String name, bool sent) => sent
    ? 'Sent. $name stays on your list until you reply.'
    : 'Your note is ready in the chat. $name stays on your list.';

/// "Bring it back" wording, kept with the sheet.
String heldTag(DateTime? until, DateTime now) => until == null
    ? 'held'
    : 'held · reply ${whenLabel(until, now).replaceFirst('at ', 'by ')}';
