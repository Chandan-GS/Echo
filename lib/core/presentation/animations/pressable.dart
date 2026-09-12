import 'package:flutter/material.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';

/// Wraps any tappable child with a subtle "press down" scale so touches feel
/// physical. Scales toward [pressedScale] on touch-down and springs back on
/// release — the small overshoot is what makes it feel premium rather than
/// mechanical.
///
/// Use for buttons, cards, list rows, chips — anything the user taps.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;

  /// When false the child renders as-is with no gesture handling (useful for
  /// disabled states) so callers don't have to conditionally unwrap it.
  final bool enabled;

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.96,
    this.enabled = true,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  bool get _active => widget.enabled && widget.onTap != null;

  void _setPressed(bool value) {
    if (!_active || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _active ? widget.onTap : null,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: _pressed ? AppMotion.fast : AppMotion.medium,
        curve: _pressed ? AppMotion.standard : AppMotion.spring,
        child: widget.child,
      ),
    );
  }
}
