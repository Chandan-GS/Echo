import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/presentation/widgets/press_feedback.dart';
import 'package:project_echo/core/services/gemini_usage.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_mascot.dart';
import 'package:project_echo/features/history/presentation/widgets/history_parts.dart';
import 'package:project_echo/features/quiet/data/quiet_held.dart';

/// "9 AM", or "9:30 AM" when the minutes matter.
String quietClock(DateTime t) => clockTime(t).replaceFirst(':00', '');

/// "9 AM" for [minutes] after midnight.
String quietClockOf(int minutes) =>
    quietClock(DateTime(2000, 1, 1, minutes ~/ 60, minutes % 60));

/// "1:19:46" until [left] runs out.
String quietCountdown(Duration left) {
  final s = left.inSeconds < 0 ? 0 : left.inSeconds;
  final m = (s % 3600) ~/ 60;
  final x = s % 60;
  return '${s ~/ 3600}:${m.toString().padLeft(2, '0')}:${x.toString().padLeft(2, '0')}';
}

/// The ring counting down what's left of the window, with Echo asleep in it.
class QuietRing extends StatelessWidget {
  final double progress;
  final String label;
  final String caption;
  final bool asleep;

  const QuietRing({
    super.key,
    required this.progress,
    required this.label,
    required this.caption,
    required this.asleep,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      width: 176,
      height: 176,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: progress.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 900),
        curve: const Cubic(0.2, 0.8, 0.2, 1),
        builder: (context, value, child) => CustomPaint(
          painter: _RingPainter(
            value,
            c.primaryGreen,
            c.primaryGreen.withValues(alpha: 0.13),
          ),
          child: child,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              EchoMascot(
                state: asleep ? EchoState.sleeping : EchoState.idle,
                size: 64,
                showRings: false,
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: GoogleFonts.nunito(
                    fontSize: 22,
                    letterSpacing: 0.3,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Text(
                caption,
                maxLines: 1,
                style: GoogleFonts.nunito(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: c.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color track;
  const _RingPainter(this.progress, this.color, this.track);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 8;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, paint..color = track);
    if (progress <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      paint..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color || old.track != track;
}

/// A row of the "Getting through" card.
class QuietRow extends StatelessWidget {
  final IconData icon;
  final bool green;
  final String title;
  final String value;
  final Widget? extra;
  final Widget trailing;
  final VoidCallback? onTap;

  const QuietRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.trailing,
    this.green = false,
    this.extra,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(14, 13, 10, 13),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: green
                  ? context.selectionFill
                  : Color.lerp(c.background, c.surface, 0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 19,
              fill: green ? 1 : 0,
              color: green ? context.onSelection : c.textPrimary,
            ),
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
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: GoogleFonts.nunito(
                    fontSize: 12.5,
                    height: 1.35,
                    color: c.textSecondary,
                  ),
                ),
                if (extra != null) ...[const SizedBox(height: 6), extra!],
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
    if (onTap == null) return row;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(onTap: onTap, child: row),
    );
  }
}

/// "Always" beside what quiet hours can never hold.
class QuietLock extends StatelessWidget {
  const QuietLock({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.dividerColor.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Symbols.lock_rounded, size: 14, fill: 1, color: c.textSecondary),
          const SizedBox(width: 4),
          Text(
            'Always',
            style: GoogleFonts.nunito(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: c.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Held notifications as a stack that opens up: one app's, or several small
/// apps' together.
class HeldStack extends StatefulWidget {
  final String title;
  final Widget icon;
  final int count;
  final String who;
  final String preview;
  final List<RawData> items;
  final int shownLimit;
  final bool muted;

  const HeldStack({
    super.key,
    required this.title,
    required this.icon,
    required this.count,
    required this.who,
    required this.preview,
    required this.items,
    this.shownLimit = 12,
    this.muted = false,
  });

  factory HeldStack.forGroup(HeldGroup group, {Key? key}) {
    final first = group.items.first;
    return HeldStack(
      key: key,
      title: group.source,
      icon: HistoryAppIcon(source: group.source),
      count: group.count,
      who: group.who,
      preview: '${first.sender.isEmpty ? first.who : first.sender.split(' · ').first}: ${first.content}',
      items: group.items,
    );
  }

  @override
  State<HeldStack> createState() => _HeldStackState();
}

class _HeldStackState extends State<HeldStack> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final layers = widget.count >= 3 ? 2 : (widget.count == 2 ? 1 : 0);
    final borderColor = c.dividerColor.withValues(alpha: 0.5);
    final items = widget.items.take(widget.shownLimit).toList();
    final hidden = widget.count - items.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PressFeedback(
            scale: 0.985,
            haptic: false,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _open = !_open),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        widget.icon,
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.nunito(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: widget.muted
                                  ? c.textSecondary
                                  : c.primaryGreen,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: c.dividerColor.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${widget.count}',
                            style: GoogleFonts.nunito(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                        AnimatedRotation(
                          turns: _open ? 0.5 : 0,
                          duration: const Duration(milliseconds: 260),
                          child: Icon(
                            Symbols.expand_more_rounded,
                            size: 20,
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.who,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.nunito(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        height: 1.4,
                        color: c.textPrimary.withValues(alpha: 0.8),
                      ),
                    ),
                    AnimatedSize(
                      duration: AppMotion.medium,
                      curve: AppMotion.emphasized,
                      alignment: Alignment.topCenter,
                      child: _open
                          ? Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final item in items)
                                    HeldLine(entry: item),
                                  if (hidden > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        'and $hidden more, all in History',
                                        style: GoogleFonts.nunito(
                                          fontSize: 13,
                                          color: c.textSecondary,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                  ],
                ),
              ),
            ),
          ),
          for (var i = 0; i < layers; i++)
            Container(
              height: 6,
              margin: EdgeInsets.symmetric(horizontal: 10.0 * (i + 1)),
              decoration: BoxDecoration(
                color: Color.lerp(c.surface, c.background, 0.4 + i * 0.25),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(14),
                ),
                border: Border(
                  left: BorderSide(color: borderColor),
                  right: BorderSide(color: borderColor),
                  bottom: BorderSide(color: borderColor),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A held message on one line of a stack or the digest.
class HeldLine extends StatelessWidget {
  final RawData entry;
  final bool withIcon;
  const HeldLine({super.key, required this.entry, this.withIcon = false});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: c.dividerColor.withValues(alpha: 0.6)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (withIcon) ...[
            HistoryAppIcon(source: entry.source, size: 16),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.who,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
                Text(
                  entry.content,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    height: 1.35,
                    color: c.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            clockTime(entry.timestamp),
            style: GoogleFonts.nunito(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: c.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
