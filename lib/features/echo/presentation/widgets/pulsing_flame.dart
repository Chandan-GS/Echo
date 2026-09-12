import 'dart:math';
import 'package:flutter/material.dart';

/// The 🔥 emoji gently "breathing" — scaling up and down on a loop — over an
/// optional soft radial glow. Deliberately simple (the emoji, not a bespoke
/// vector flame), matching the look we settled on.
class PulsingFlame extends StatefulWidget {
  /// Font size of the emoji. The overall box is a bit larger to fit the glow.
  final double size;
  final bool glow;

  const PulsingFlame({super.key, this.size = 64, this.glow = true});

  @override
  State<PulsingFlame> createState() => _PulsingFlameState();
}

class _PulsingFlameState extends State<PulsingFlame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final box = widget.size * 2.3;
    return SizedBox(
      width: box,
      height: box,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final pulse = 0.9 + 0.1 * sin(_c.value * 2 * pi);
          return Stack(
            alignment: Alignment.center,
            children: [
              if (widget.glow)
                Container(
                  width: box * pulse,
                  height: box * pulse,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFFFF8A3D).withValues(alpha: 0.35),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              Transform.scale(
                scale: pulse,
                child: Text('🔥', style: TextStyle(fontSize: widget.size)),
              ),
            ],
          );
        },
      ),
    );
  }
}
