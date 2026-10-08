import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:project_echo/core/presentation/launch_echo.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_mascot.dart';

/// For someone who has set up already: the splash's sleeping Echo carries on
/// over the app's first frame, wakes, smiles, and fades into Home. About 1.3
/// seconds. The splash hands over to its first frame without a seam (see
/// [LaunchEcho]).
class LaunchWake extends StatefulWidget {
  final Widget child;
  const LaunchWake({super.key, required this.child});

  @override
  State<LaunchWake> createState() => _LaunchWakeState();
}

class _LaunchWakeState extends State<LaunchWake>
    with SingleTickerProviderStateMixin {
  static const _length = 1.3; // seconds

  late final AnimationController _c =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1300),
      )..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) {
          setState(() => _done = true);
        }
      });
  bool _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // With animations turned off, straight to the app.
      if (MediaQuery.of(context).disableAnimations) {
        setState(() => _done = true);
      } else {
        _c.forward();
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static double _smooth(double x) => x * x * (3 - 2 * x);
  static double _span(double t, double a, double b) =>
      _smooth(((t - a) / (b - a)).clamp(0.0, 1.0));
  static double _lerp(double a, double b, double x) => a + (b - a) * x;

  @override
  Widget build(BuildContext context) {
    // The app keeps its place in the tree when the veil goes, so nothing
    // under it is rebuilt.
    return Stack(
      children: [
        widget.child,
        if (!_done)
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) => _veil(context, _c.value * _length),
          ),
      ],
    );
  }

  Widget _veil(BuildContext context, double t) {
    final wake = _span(t, 0.25, 0.55);
    final state = t < 0.3
        ? EchoState.sleeping
        : t > 0.5 && t < 0.85
        ? EchoState.happy
        : EchoState.idle;
    final hop = t > 0.45 && t < 0.8
        ? 8 * math.sin((t - 0.45) / 0.35 * math.pi)
        : 0.0;
    final away = _span(t, 0.85, 1.25);
    const size = LaunchEcho.mascotSize;
    return IgnorePointer(
      ignoring: away > 0,
      child: Opacity(
        opacity: 1 - away,
        child: ColoredBox(
          color: LaunchEcho.ground,
          child: LayoutBuilder(
            builder: (context, box) => Stack(
              children: [
                Positioned(
                  left: box.maxWidth / 2 - size / 2,
                  top:
                      LaunchEcho.centerY(context, box.maxHeight) -
                      hop -
                      size / 2,
                  width: size,
                  height: size,
                  // The same EchoMascot throughout, so his own float and
                  // blink carry on through the wake.
                  child: Opacity(
                    opacity: _lerp(LaunchEcho.asleep, 1, wake),
                    child: EchoMascot(
                      state: state,
                      size: size,
                      showRings: false,
                      glow: false,
                      zzz: 0,
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
