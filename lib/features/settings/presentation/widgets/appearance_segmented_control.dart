import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_state.dart';

class AppearanceSegmentedControl extends StatelessWidget {
  const AppearanceSegmentedControl({super.key});

  @override
  Widget build(BuildContext context) {
    final tabs = ['System', 'Light', 'Dark'];

    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        final selectedIndex = state.themeMode.index;

        return Container(
          height: 60,
          width: double.infinity,
          decoration: BoxDecoration(
            color: context.colors.textInverse,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: context.colors.dividerColor.withOpacity(0.5),
            ),
          ),
          padding: const EdgeInsets.all(6),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final totalWidth = constraints.maxWidth;
              final itemWidth = totalWidth / 3;
              final activeLeft = selectedIndex * itemWidth;

              return Stack(
                children: [
                  // Fluid sliding active capsule
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutBack,
                    left: activeLeft,
                    top: 0,
                    bottom: 0,
                    width: itemWidth,
                    child: Container(
                      decoration: BoxDecoration(
                        color: context.colors.textPrimary,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  // Tab Items Row
                  Row(
                    children: List.generate(tabs.length, (index) {
                      final title = tabs[index];
                      final isSelected = selectedIndex == index;

                      return Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            context.read<SettingsCubit>().setThemeMode(
                              ThemeMode.values[index],
                            );
                          },
                          child: Center(
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 200),
                              style: GoogleFonts.nunito(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? context.colors.textInverse
                                    : context.colors.textSecondary,
                              ),
                              child: Text(title),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
