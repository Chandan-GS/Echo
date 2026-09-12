import 'package:flutter/material.dart';

/// Echo's on-brand mark for the "Today" tab: five bars in a symmetric hump —
/// the same silhouette as an audio level meter / waveform, echoing the motif
/// used everywhere audio plays in the app (the welcome screen,
/// [SiriWaveformVisualizer], voice previews) — a house icon said nothing about
/// what this app actually does.
///
/// Whenever [active] changes, the bars animate to their new shape with a
/// staggered "wave waking up" ripple, so selecting this tab always feels live.
class EchoWaveIcon extends StatefulWidget {
  final bool active;
  final Color color;
  final double size;

  const EchoWaveIcon({
    super.key,
    required this.active,
    required this.color,
    this.size = 26,
  });

  @override
  State<EchoWaveIcon> createState() => _EchoWaveIconState();
}

class _EchoWaveIconState extends State<EchoWaveIcon>
    with SingleTickerProviderStateMixin {
  // Symmetric hump envelopes (relative to size) — reads as a soundwave.
  static const _calm = [0.32, 0.5, 0.62, 0.5, 0.32];
  static const _live = [0.45, 0.8, 1.0, 0.8, 0.45];

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  late List<double> _from = widget.active ? _live : _calm;
  late List<double> _to = _from;

  @override
  void didUpdateWidget(covariant EchoWaveIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) {
      _from = oldWidget.active ? _live : _calm;
      _to = widget.active ? _live : _calm;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final barWidth = widget.size / 7.5;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(_calm.length, (i) {
              // Staggered per-bar start so the wave ripples left-to-right.
              final start = i * 0.08;
              final progress = CurvedAnimation(
                parent: _controller,
                curve: Interval(
                  start,
                  (start + 0.7).clamp(0.0, 1.0),
                  curve: Curves.easeOutBack,
                ),
              ).value;
              final h = _from[i] + (_to[i] - _from[i]) * progress;
              return Container(
                width: barWidth,
                height:
                    (widget.size * h).clamp(widget.size * 0.15, widget.size),
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(barWidth / 2),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
