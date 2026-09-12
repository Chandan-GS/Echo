import 'package:flutter/material.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';

/// The single source of truth for how many setup steps the onboarding has.
/// Every step screen passes its own 1-based index to [OnboardingProgress].
const int kOnboardingTotalSteps = 6;

/// One solid, continuous progress bar that fills left-to-right as the user moves
/// through setup. No step counters, no percentages — a single deliberate line.
/// The fill animates smoothly between steps.
class OnboardingProgress extends StatelessWidget {
  final int step; // 1-based
  final int totalSteps;

  const OnboardingProgress({
    super.key,
    required this.step,
    this.totalSteps = kOnboardingTotalSteps,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final target = (step / totalSteps).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return SizedBox(
          height: 8,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              children: [
                Container(color: colors.dividerColor),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: target),
                  duration: AppMotion.slow,
                  curve: AppMotion.emphasized,
                  builder: (context, value, _) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: width * value,
                        decoration: BoxDecoration(
                          color: colors.primaryGreen,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
