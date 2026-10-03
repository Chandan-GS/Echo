import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';

/// Makes a press felt: [child] sinks a little under the finger and springs
/// back when it lifts, with a light tap of the phone. It only listens, so
/// the child's own taps and ripples work as before; and when the finger
/// moves off to scroll, it lets go without the tap.
class PressFeedback extends StatefulWidget {
  final Widget child;

  /// How far it sinks: 0.95 for buttons, nearer 1 for wide rows.
  final double scale;

  /// Whether lifting the finger taps the phone.
  final bool haptic;

  /// Nothing happens when false (a disabled button).
  final bool enabled;

  const PressFeedback({
    super.key,
    required this.child,
    this.scale = 0.95,
    this.haptic = true,
    this.enabled = true,
  });

  @override
  State<PressFeedback> createState() => _PressFeedbackState();
}

class _PressFeedbackState extends State<PressFeedback> {
  bool _down = false;
  Offset? _from;

  /// Further than this and it's a scroll, not a press.
  static const _slop = 12.0;

  void _release({required bool tapped}) {
    if (!_down) return;
    setState(() => _down = false);
    if (tapped && widget.haptic) HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Listener(
      onPointerDown: (e) {
        _from = e.position;
        setState(() => _down = true);
      },
      onPointerMove: (e) {
        if (_from != null && (e.position - _from!).distance > _slop) {
          _release(tapped: false);
        }
      },
      onPointerUp: (_) => _release(tapped: true),
      onPointerCancel: (_) => _release(tapped: false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        // In quickly; back out with a little spring.
        duration: _down ? const Duration(milliseconds: 90) : AppMotion.medium,
        curve: _down ? Curves.easeOut : AppMotion.spring,
        child: widget.child,
      ),
    );
  }
}
