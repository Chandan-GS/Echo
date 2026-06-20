import 'package:flutter/material.dart';
import 'package:siri_wave/siri_wave.dart';
import 'package:project_echo/core/theme/app_theme.dart';

/// Siri-style waveform visualizer with an integrated tap-to-play/pause gesture.
/// A brief animated overlay icon appears on tap and fades out after 1.2 seconds.
class SiriWaveformVisualizer extends StatefulWidget {
  final bool isPlaying;
  final VoidCallback onTap;

  const SiriWaveformVisualizer({
    super.key,
    required this.isPlaying,
    required this.onTap,
  });

  @override
  State<SiriWaveformVisualizer> createState() => _SiriWaveformVisualizerState();
}

class _SiriWaveformVisualizerState extends State<SiriWaveformVisualizer>
    with SingleTickerProviderStateMixin {
  late IOS9SiriWaveformController _waveController;
  late AnimationController _iconFadeController;
  late Animation<double> _iconOpacity;

  @override
  void initState() {
    super.initState();

    _waveController = IOS9SiriWaveformController(
      amplitude: widget.isPlaying ? 1.0 : 0.05,
      color1: AppTheme.primaryGreen,
      color2: AppTheme.textPrimary,
      color3: AppTheme.lightGreenBackground,
    );

    _iconFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _iconOpacity = CurvedAnimation(
      parent: _iconFadeController,
      curve: Curves.easeOut,
    );
  }

  @override
  void didUpdateWidget(covariant SiriWaveformVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      _waveController.amplitude = widget.isPlaying ? 1.0 : 0.05;
    }
  }

  @override
  void dispose() {
    _iconFadeController.dispose();
    super.dispose();
  }

  void _handleTap() {
    widget.onTap();
    // Briefly flash the icon then fade it out
    _iconFadeController.forward(from: 0.0).then((_) {
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) _iconFadeController.reverse();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 180,
        width: double.infinity,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Waveform
            SiriWaveform.ios9(
              controller: _waveController,
              options: const IOS9SiriWaveformOptions(height: 180),
            ),

            // Tap feedback icon — fades in then out
            FadeTransition(
              opacity: _iconOpacity,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppTheme.backgroundLight.withValues(alpha: 0.85),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 16,
                    )
                  ],
                ),
                child: Icon(
                  widget.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  size: 28,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
