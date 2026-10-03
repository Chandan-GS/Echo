import 'package:flutter/material.dart';
import 'package:siri_wave/siri_wave.dart';
import 'package:project_echo/core/theme/app_theme.dart';

/// Siri-style waveform visualizer with an integrated tap-to-play/pause gesture.
class SiriWaveformVisualizer extends StatefulWidget {
  final bool isPlaying;
  final VoidCallback onTap;
  final double amplitude;
  final double height;

  /// Optional color overrides for the three wave layers. When null, the
  /// theme's green palette is used. Provide light colors when the visualizer
  /// sits on a dark/green gradient background.
  final Color? color1;
  final Color? color2;
  final Color? color3;

  const SiriWaveformVisualizer({
    super.key,
    required this.isPlaying,
    required this.onTap,
    required this.amplitude,
    this.height = 180,
    this.color1,
    this.color2,
    this.color3,
  });

  @override
  State<SiriWaveformVisualizer> createState() => _SiriWaveformVisualizerState();
}

class _SiriWaveformVisualizerState extends State<SiriWaveformVisualizer> {
  IOS9SiriWaveformController? _waveController;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _waveController ??= IOS9SiriWaveformController(
      amplitude: widget.isPlaying ? widget.amplitude : 0.5,
      color1: widget.color1 ?? context.colors.primaryGreen,
      color2: widget.color2 ?? context.colors.textPrimary,
      color3: widget.color3 ?? context.colors.lightGreenBackground,
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
    super.dispose();
  }

  void _handleTap() {
    widget.onTap();
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
