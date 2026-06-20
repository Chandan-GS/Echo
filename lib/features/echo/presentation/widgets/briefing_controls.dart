import 'package:flutter/material.dart';
import 'package:project_echo/core/theme/app_theme.dart';

class BriefingControls extends StatelessWidget {
  final bool isPlaying;
  final double progress;
  final VoidCallback onTogglePlay;

  const BriefingControls({
    super.key,
    required this.isPlaying,
    required this.progress,
    required this.onTogglePlay,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Progress slider
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: AppTheme.textPrimary,
              inactiveTrackColor: AppTheme.textSecondary.withValues(
                alpha: 0.15,
              ),
              thumbColor: AppTheme.textPrimary,
            ),
            child: Slider(value: progress.clamp(0.0, 1.0), onChanged: (_) {}),
          ),
        ),
        const SizedBox(height: 16),
        // Controls
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.replay_10_rounded, size: 30),
              color: AppTheme.textSecondary,
              onPressed: () {},
            ),
            const SizedBox(width: 32),
            GestureDetector(
              onTap: onTogglePlay,
              child: Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: AppTheme.textPrimary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.textPrimary.withValues(alpha: 0.25),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    )
                  ],
                ),
                child: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 36,
                  color: AppTheme.backgroundLight,
                ),
              ),
            ),
            const SizedBox(width: 32),
            IconButton(
              icon: const Icon(Icons.forward_10_rounded, size: 30),
              color: AppTheme.textSecondary,
              onPressed: () {},
            ),
          ],
        ),
      ],
    );
  }
}
