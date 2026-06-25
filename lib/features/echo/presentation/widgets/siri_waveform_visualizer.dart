import 'package:flutter/material.dart';
import 'package:siri_wave/siri_wave.dart';
import 'package:project_echo/core/theme/app_theme.dart';

/// Siri-style waveform visualizer with an integrated tap-to-play/pause gesture.
/// A brief animated overlay icon appears on tap and fades out after 1.2 seconds.
class SiriWaveformVisualizer extends StatefulWidget {
  final bool isPlaying;
  final VoidCallback onTap;
  final double amplitude;
  final double height;

  const SiriWaveformVisualizer({
    super.key,
    required this.isPlaying,
    required this.onTap,
    required this.amplitude,
    this.height = 180,
  });

  @override
  State<SiriWaveformVisualizer> createState() => _SiriWaveformVisualizerState();
}

class _SiriWaveformVisualizerState extends State<SiriWaveformVisualizer>
    with SingleTickerProviderStateMixin {
  IOS9SiriWaveformController? _waveController;
  late AnimationController _iconFadeController;
  late Animation<double> _iconOpacity;

  @override
  void initState() {
    super.initState();

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    _waveController ??= IOS9SiriWaveformController(
      amplitude: widget.isPlaying ? widget.amplitude : 0.5,
      color1: context.colors.primaryGreen,
      color2: context.colors.textPrimary,
      color3: context.colors.lightGreenBackground,
    );
  }

  @override
  void didUpdateWidget(covariant SiriWaveformVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      _waveController?.amplitude = widget.isPlaying ? widget.amplitude : 0.5;
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
        height: widget.height,
        width: double.infinity,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SiriWaveform.ios9(
              controller: _waveController!,
              options: IOS9SiriWaveformOptions(height: widget.height),
            ),
          ],
        ),
      ),
    );
  }
}
