import 'dart:async';
import 'package:flutter/material.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';

/// A one-shot entrance animation: the child fades in while sliding up a few
/// pixels. Give successive items an increasing [delay] (see
/// [AppMotion.staggerDelay]) to get a cascading "content assembling itself"
/// effect that reads as premium.
///
/// Runs once when first built and then leaves the child untouched, so it is
/// safe to place inside lists and rebuilding parents.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;

  /// Vertical offset (logical px) the child travels while entering.
  final double offsetY;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = AppMotion.medium,
    this.offsetY = 16,
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  late final Animation<double> _curved = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.emphasized,
  );

  Timer? _startTimer;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      // Cancelable so a torn-down widget (fast navigation) leaves no pending
      // timer.
      _startTimer = Timer(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _startTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curved,
      builder: (context, child) {
        return Opacity(
          opacity: _curved.value,
          child: Transform.translate(
            offset: Offset(0, (1 - _curved.value) * widget.offsetY),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Wraps each child in [children] with a staggered [FadeSlideIn]. Convenient
/// for column/list content where you want the whole group to cascade in.
List<Widget> staggeredColumn(
  List<Widget> children, {
  Duration initialDelay = Duration.zero,
  double offsetY = 16,
}) {
  return List<Widget>.generate(children.length, (i) {
    return FadeSlideIn(
      delay: initialDelay + AppMotion.staggerDelay(i),
      offsetY: offsetY,
      child: children[i],
    );
  });
}
