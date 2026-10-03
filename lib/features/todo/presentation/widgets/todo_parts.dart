import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:project_echo/core/presentation/animations/fade_slide_in.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/ask_parts.dart';

/// Pieces of the to-do list shared by the To-do tab and the desktop card.

/// Keeps a just-ticked row in place while its check and strike-through
/// play, then folds it away and calls [onGone]. Always in the tree (not
/// only while leaving) so the row's own check animation isn't remounted.
class Leavable extends StatefulWidget {
  final bool leaving;
  final VoidCallback onGone;
  final Widget child;

  const Leavable({
    super.key,
    required this.leaving,
    required this.onGone,
    required this.child,
  });

  @override
  State<Leavable> createState() => _LeavableState();
}

class _LeavableState extends State<Leavable>
    with SingleTickerProviderStateMixin {
  static const _hold = Duration(milliseconds: 650);

  late final AnimationController _present = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
    value: 1,
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.leaving) _scheduleLeave();
  }

  @override
  void didUpdateWidget(covariant Leavable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.leaving && !oldWidget.leaving) _scheduleLeave();
    if (!widget.leaving && oldWidget.leaving) {
      // Unticked before it left: stay.
      _timer?.cancel();
      _present.forward();
    }
  }

  void _scheduleLeave() {
    _timer?.cancel();
    _timer = Timer(_hold, () async {
      if (!mounted) return;
      await _present.reverse();
      if (mounted && widget.leaving) widget.onGone();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _present.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(
      parent: _present,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return SizeTransition(
      sizeFactor: curve,
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: curve,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0.06, 0),
            end: Offset.zero,
          ).animate(curve),
          child: widget.child,
        ),
      ),
    );
  }
}

class ProgressRing extends StatelessWidget {
  final int done;
  final int total;
  const ProgressRing({super.key, required this.done, required this.total});

  @override
  Widget build(BuildContext context) {
    final target = total == 0 ? 0.0 : done / total;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: target),
      duration: const Duration(milliseconds: 600),
      curve: const Cubic(0.2, 0.8, 0.2, 1),
      builder: (context, value, _) => SizedBox(
        width: 52,
        height: 52,
        child: CustomPaint(
          painter: _RingPainter(
            value: value,
            track: context.colors.primaryGreen.withValues(
              alpha: context.isDarkMode ? 0.14 : 0.10,
            ),
            fill: context.colors.primaryGreen,
          ),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              transitionBuilder: (child, a) =>
                  ScaleTransition(scale: a, child: child),
              child: total > 0 && done == total
                  ? Icon(
                      Symbols.check_rounded,
                      key: const ValueKey('all-done'),
                      size: 24,
                      color: context.colors.primaryGreen,
                    )
                  : Text(
                      '$done',
                      key: const ValueKey('count'),
                      style: GoogleFonts.nunito(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: context.colors.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final Color track;
  final Color fill;
  _RingPainter({required this.value, required this.track, required this.fill});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(3);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, stroke..color = track);
    if (value > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * value,
        false,
        stroke..color = fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.value != value || old.track != track || old.fill != fill;
}

class UpdateRow extends StatelessWidget {
  final int count;
  final DateTime? since;
  final VoidCallback onUpdate;
  const UpdateRow({
    super.key,
    required this.count,
    required this.since,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // A quiet row like Home's Regenerate, with the one button in it.
    return FadeSlideIn(
      offsetY: -6,
      child: Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Material(
          color: c.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: c.dividerColor.withValues(alpha: 0.6)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Icon(Symbols.forum_rounded, size: 20, color: c.textSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$count new',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: c.textPrimary,
                          ),
                        ),
                        if (since != null)
                          TextSpan(text: ' since ${clockLabel(since!)}'),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.nunito(
                      fontSize: 14,
                      color: c.textSecondary,
                    ),
                  ),
                ),
                AskPill(
                  label: 'Update',
                  icon: Symbols.refresh_rounded,
                  filled: true,
                  onTap: onUpdate,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown when today's list is finished: a green badge whose tick draws itself,
/// "That's everything for today", and when the last item was done.
class AllDonePanel extends StatefulWidget {
  final int count;
  final DateTime? lastDoneAt;
  const AllDonePanel({
    super.key,
    required this.count,
    required this.lastDoneAt,
  });

  @override
  State<AllDonePanel> createState() => _AllDonePanelState();
}

class _AllDonePanelState extends State<AllDonePanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  late final Animation<double> _rise = CurvedAnimation(
    parent: _in,
    curve: const Interval(0, 0.55, curve: Cubic(0.2, 0.8, 0.2, 1)),
  );
  late final Animation<double> _pop = CurvedAnimation(
    parent: _in,
    curve: const Interval(0.12, 0.7, curve: Cubic(0.34, 1.56, 0.64, 1)),
  );
  late final Animation<double> _tick = CurvedAnimation(
    parent: _in,
    curve: const Interval(0.45, 0.85, curve: Curves.easeOut),
  );

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final last = widget.lastDoneAt;
    return AnimatedBuilder(
      animation: _in,
      builder: (context, _) => Opacity(
        opacity: _rise.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - _rise.value)),
          child: Container(
            margin: const EdgeInsets.fromLTRB(0, 14, 0, 6),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.primaryGreen.withValues(
                alpha: context.isDarkMode ? 0.14 : 0.10,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Transform.scale(
                  scale: _pop.value,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: c.primaryGreen,
                      shape: BoxShape.circle,
                    ),
                    child: CustomPaint(
                      painter: _CheckPainter(
                        _tick.value,
                        context.isDarkMode
                            ? const Color(0xFF16301B)
                            : Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "That's everything for today",
                        style: GoogleFonts.nunito(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        last == null
                            ? '${widget.count} done'
                            : '${widget.count} done · last one at ${clockLabel(last)}',
                        style: GoogleFonts.nunito(
                          fontSize: 13,
                          color: c.textSecondary,
                        ),
                      ),
                    ],
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

/// Opens and closes [child] by growing and fading it together. The child
/// stays built while closed, so it never pops in mid-animation.
class Reveal extends StatefulWidget {
  static const duration = Duration(milliseconds: 260);
  static const curve = Curves.easeOutCubic;

  final bool open;
  final Widget child;
  const Reveal({super.key, required this.open, required this.child});

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Reveal.duration,
    value: widget.open ? 1 : 0,
  );
  late final Animation<double> _size = CurvedAnimation(
    parent: _c,
    curve: Reveal.curve,
    reverseCurve: Curves.easeInCubic,
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.25, 1, curve: Curves.easeOut),
    reverseCurve: const Interval(0.4, 1, curve: Curves.easeIn),
  );

  @override
  void didUpdateWidget(covariant Reveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open != oldWidget.open) {
      widget.open ? _c.forward() : _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: _size,
      alignment: Alignment.topCenter,
      child: FadeTransition(opacity: _fade, child: widget.child),
    );
  }
}

/// A brief green wash behind a line that just changed (e.g. a moved time).
class ChangeHighlight extends StatelessWidget {
  final bool active;
  final Widget child;
  const ChangeHighlight({super.key, required this.active, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!active) return child;
    final tint = context.colors.primaryGreen.withValues(
      alpha: context.isDarkMode ? 0.14 : 0.10,
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1200),
      builder: (context, t, child) {
        final a = t < 0.3 ? t / 0.3 : (1 - t) / 0.7;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: Color.lerp(Colors.transparent, tint, a.clamp(0.0, 1.0)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: child,
        );
      },
      child: child,
    );
  }
}

class TodoCheck extends StatelessWidget {
  final bool done;
  final VoidCallback onTap;
  final String label;
  const TodoCheck({
    super.key,
    required this.done,
    required this.onTap,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final green = context.colors.primaryGreen;
    return Semantics(
      button: true,
      checked: done,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.only(top: 1),
          child: AnimatedScale(
            scale: done ? 1.08 : 1,
            duration: const Duration(milliseconds: 220),
            curve: const Cubic(0.34, 1.56, 0.64, 1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? green : Colors.transparent,
                border: Border.all(
                  color: done ? green : green.withValues(alpha: 0.55),
                  width: 2,
                ),
              ),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: done ? 1 : 0),
                duration: const Duration(milliseconds: 280),
                builder: (context, t, _) => CustomPaint(
                  painter: _CheckPainter(
                    t,
                    context.isDarkMode ? const Color(0xFF16301B) : Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  final double t;
  final Color color;
  _CheckPainter(this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * 0.28, h * 0.52)
      ..lineTo(w * 0.44, h * 0.67)
      ..lineTo(w * 0.72, h * 0.36);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * t),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _CheckPainter old) =>
      old.t != t || old.color != color;
}
