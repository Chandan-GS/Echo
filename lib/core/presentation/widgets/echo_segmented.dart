import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';

/// A row of choices in one capsule, the chosen one in a dark pill that
/// slides to it (Appearance's System / Light / Dark).
class EchoSegmented extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  const EchoSegmented({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 60,
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.textInverse,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: c.dividerColor.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.all(6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = constraints.maxWidth / labels.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutBack,
                left: selected * itemWidth,
                top: 0,
                bottom: 0,
                width: itemWidth,
                child: Container(
                  decoration: BoxDecoration(
                    color: c.textPrimary,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final (i, label) in labels.indexed)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (i == selected) return;
                          HapticFeedback.selectionClick();
                          onSelect(i);
                        },
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: GoogleFonts.nunito(
                              fontSize: labels.length > 3 ? 14.5 : 16,
                              fontWeight: FontWeight.bold,
                              color: i == selected
                                  ? c.textInverse
                                  : c.textSecondary,
                            ),
                            child: Text(label),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
