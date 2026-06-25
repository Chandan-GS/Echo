import 'package:flutter/material.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import '../../../../core/presentation/widgets/chip_label.dart';

class AiModeCard extends StatelessWidget {
  final bool isSelected;
  final IconData icon;
  final String title;
  final List<String> tags;
  final String speedLabel;
  final bool isFast;
  final VoidCallback onTap;
  final Widget? expandedContent;

  const AiModeCard({
    Key? key,
    required this.isSelected,
    required this.icon,
    required this.title,
    required this.tags,
    required this.speedLabel,
    required this.isFast,
    required this.onTap,
    this.expandedContent,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: EdgeInsets.all(isSelected ? 19 : 20),
        decoration: BoxDecoration(
          color: context.colors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? context.colors.primaryGreen
                : context.colors.dividerColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOutBack,
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: context.colors.primaryGreen, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? context.colors.primaryGreen
                            : context.colors.dividerColor,
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? Center(
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: context.colors.primaryGreen,
                              ),
                            ),
                          )
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: tags
                    .map((tag) => ChipLabel(text: tag, isOutline: true))
                    .toList(),
              ),
              const SizedBox(height: 16),
              Divider(color: context.colors.dividerColor, height: 1),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    isFast ? Icons.bolt : Icons.hourglass_empty,
                    size: 16,
                    color: context.colors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Processing speed:',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(width: 8),
                  ChipLabel(
                    text: speedLabel,
                    isOutline: false,
                    backgroundColor: isFast
                        ? context.colors.lightGreenBackground
                        : context.colors.amberBackground,
                    textColor: context.colors.textPrimary,
                  ),
                ],
              ),
              if (expandedContent != null && isSelected) ...[
                const SizedBox(height: 16),
                Divider(color: context.colors.dividerColor, height: 1),
                const SizedBox(height: 16),
                expandedContent!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
