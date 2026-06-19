import 'package:flutter/material.dart';
import 'package:project_echo/core/theme/app_theme.dart';

class StepIndicator extends StatelessWidget {
  final int currentStep;
  final int totalSteps;

  const StepIndicator({
    Key? key,
    required this.currentStep,
    required this.totalSteps,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: List.generate(totalSteps, (index) {
            bool isActive = index == (currentStep - 1);
            return Container(
              margin: const EdgeInsets.only(right: 6),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive ? AppTheme.textPrimary : Colors.transparent,
                border: Border.all(
                  color: isActive ? AppTheme.textPrimary : const Color(0xFFC4C4C4),
                  width: 1,
                ),
              ),
            );
          }),
        ),
        const SizedBox(width: 8),
        Text(
          'STEP $currentStep OF $totalSteps',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}
