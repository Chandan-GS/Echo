import 'package:flutter/material.dart';

/// The streak flame — the app's animated fire (`assets/icons/fire.gif`).
/// The GIF animates natively; [size] is roughly the visible flame height and
/// [glow] adds a soft warm halo behind it.
class StreakFlame extends StatelessWidget {
  final double size;
  final bool glow;

  const StreakFlame({super.key, this.size = 40, this.glow = true});

  @override
  Widget build(BuildContext context) {
    // The flame occupies ~70% of the GIF's square canvas, so scale the box up
    // a touch to make the visible flame about [size] tall.
    final box = size * 1.4;
    final img = Image.asset(
      'assets/icons/fire.gif',
      width: box,
      height: box,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
    );

    if (!glow) return SizedBox(width: box, height: box, child: img);

    return SizedBox(
      width: box,
      height: box,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: box * 0.86,
            height: box * 0.86,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFFFF9A00).withValues(alpha: 0.16),
                  Colors.transparent,
                ],
                stops: const [0.2, 1.0],
              ),
            ),
          ),
          img,
        ],
      ),
    );
  }
}
