import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/presentation/widgets/press_feedback.dart';
import 'package:project_echo/core/services/reminders.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/desktop/presentation/todo/board_logic.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/ask_parts.dart';
import 'package:project_echo/features/todo/data/todo_planner.dart';

/// The field above the board: type a to-do, with its time if it has one,
/// and see as you type how Echo reads it ("tomorrow", "11:00 AM", "✦ remind
/// at 10:40 AM"). Enter adds it; Escape lets go.
class AddBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focus;
  final ValueChanged<String> onAdd;

  const AddBar({
    super.key,
    required this.controller,
    required this.focus,
    required this.onAdd,
  });

  /// The shortcut that brings the owner here, as their keyboard writes it.
  static String get shortcut =>
      defaultTargetPlatform == TargetPlatform.macOS ? '⌘N' : 'Ctrl+N';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 52,
      padding: const EdgeInsets.only(left: 16, right: 10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.dividerColor),
        boxShadow: context.isDarkMode
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.035),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Row(
        children: [
          Icon(Symbols.add_rounded, size: 20, color: c.primaryGreen),
          const SizedBox(width: 10),
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): () {
                  controller.clear();
                  focus.unfocus();
                },
              },
              child: TextField(
                controller: controller,
                focusNode: focus,
                textCapitalization: TextCapitalization.sentences,
                // Enter keeps the field focused, for the next one.
                onEditingComplete: () {},
                onSubmitted: (text) {
                  if (text.trim().isNotEmpty) onAdd(text.trim());
                },
                cursorColor: c.primaryGreen,
                style: GoogleFonts.nunito(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
                decoration: InputDecoration(
                  isCollapsed: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: 'Add a to-do… “call the plumber at 11 tomorrow”',
                  hintMaxLines: 1,
                  hintStyle: GoogleFonts.nunito(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: c.textSecondary.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => AnimatedSwitcher(
              duration: AppMotion.fast,
              child: controller.text.trim().isEmpty
                  ? _KeyCap(key: const ValueKey('key'), label: shortcut)
                  : _Preview(
                      key: const ValueKey('preview'),
                      text: controller.text,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// How Echo reads what's being typed: its day, its time, and the reminder
/// it would suggest.
class _Preview extends StatelessWidget {
  final String text;
  const _Preview({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final item = typedItem(text, 0, now);
    final at = suggestedReminder(item, now);
    final day = switch (daysBetween(now, item.day)) {
      0 => 'today',
      1 => 'tomorrow',
      _ => dayLabel(item.day),
    };
    return AnimatedSize(
      duration: AppMotion.fast,
      curve: AppMotion.emphasized,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PreviewChip(day),
          if (item.time case final time?) ...[
            const SizedBox(width: 8),
            _PreviewChip(time),
          ],
          if (at != null) ...[
            const SizedBox(width: 8),
            _PreviewChip('remind at ${clockLabel(at)}', echo: true),
          ],
        ],
      ),
    );
  }
}

class _PreviewChip extends StatelessWidget {
  final String label;

  /// Echo's suggestion, marked with its ✦.
  final bool echo;

  const _PreviewChip(this.label, {this.echo = false});

  @override
  Widget build(BuildContext context) {
    final fg = context.onSelection;
    return Container(
      height: 26,
      padding: EdgeInsets.fromLTRB(echo ? 7 : 10, 0, 10, 0),
      decoration: BoxDecoration(
        color: context.selectionFill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (echo) ...[
            Icon(Symbols.auto_awesome_rounded, size: 13, fill: 1, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: GoogleFonts.nunito(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: fg,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyCap extends StatelessWidget {
  final String label;
  const _KeyCap({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.dividerColor),
      ),
      child: Text(
        label,
        style: GoogleFonts.nunito(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: c.textSecondary,
        ),
      ),
    );
  }
}

/// Floats up from the bottom while cards are picked: "2 picked · Move to
/// tomorrow · Remind me · Done · ✕".
class BulkBar extends StatefulWidget {
  final int count;
  final VoidCallback onTomorrow;
  final VoidCallback onRemind;
  final VoidCallback onDone;
  final VoidCallback onClear;

  const BulkBar({
    super.key,
    required this.count,
    required this.onTomorrow,
    required this.onRemind,
    required this.onDone,
    required this.onClear,
  });

  @override
  State<BulkBar> createState() => _BulkBarState();
}

class _BulkBarState extends State<BulkBar> {
  /// The last count worth showing, so the bar doesn't say "0 picked" on
  /// its way out.
  late int _shown = widget.count;

  @override
  void didUpdateWidget(covariant BulkBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.count > 0) _shown = widget.count;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final on = widget.count > 0;
    // Dark on the light theme, light on the dark one, like the mock's ink.
    final fg = c.background;
    return IgnorePointer(
      ignoring: !on,
      child: AnimatedSlide(
        offset: on ? Offset.zero : const Offset(0, 2),
        duration: const Duration(milliseconds: 350),
        curve: on ? const Cubic(0.3, 1.2, 0.4, 1) : AppMotion.standard,
        child: AnimatedOpacity(
          opacity: on ? 1 : 0,
          duration: AppMotion.fast,
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 10, 10, 10),
            decoration: BoxDecoration(
              color: c.textPrimary,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 34,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$_shown picked',
                  style: GoogleFonts.nunito(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: fg,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 12),
                _BarButton(
                  label: 'Move to tomorrow',
                  color: fg,
                  onTap: widget.onTomorrow,
                ),
                const SizedBox(width: 8),
                _BarButton(
                  label: 'Remind me',
                  color: fg,
                  onTap: widget.onRemind,
                ),
                const SizedBox(width: 8),
                _BarButton(label: 'Done', color: fg, onTap: widget.onDone),
                const SizedBox(width: 8),
                _BarButton(
                  icon: Symbols.close_rounded,
                  tip: 'Let go of them',
                  color: fg,
                  onTap: widget.onClear,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final String? tip;
  final Color color;
  final VoidCallback onTap;

  const _BarButton({
    this.label,
    this.icon,
    this.tip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final button = PressFeedback(
      child: Material(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: label == null ? 8 : 12,
              vertical: 7,
            ),
            child: label != null
                ? Text(
                    label!,
                    style: GoogleFonts.nunito(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  )
                : Icon(icon, size: 17, color: color),
          ),
        ),
      ),
    );
    return tip == null ? button : Tooltip(message: tip, child: button);
  }
}
