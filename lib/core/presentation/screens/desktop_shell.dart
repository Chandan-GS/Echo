import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/presentation/animations/pressable.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_state.dart';

/// The desktop-class app frame: a persistent left sidebar for navigation
/// instead of the phone's floating bottom nav bar. Wraps the exact same
/// [content] the phone shell shows — only the surrounding chrome differs —
/// so every screen's own logic is untouched.
class DesktopShell extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;

  /// Every tab (Today, Vault, Settings) lays itself out for the full window
  /// width and owns its own internal max-width/grid — the shell just supplies
  /// the sidebar and hands over the rest of the window as-is.
  final Widget content;

  const DesktopShell({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      body: Row(
        children: [
          _Sidebar(
            selectedIndex: selectedIndex,
            onItemSelected: onItemSelected,
          ),
          Expanded(child: content),
        ],
      ),
    );
  }
}

/// The sidebar always renders in the app's dark palette, independent of the
/// user's light/dark setting — a native app rail (like VS Code's activity
/// bar or Slack's workspace rail) reads as a fixed piece of chrome, not a
/// surface that should flip with content theme.
const _sidebarColors = AppColors(
  background: AppTheme.backgroundDark,
  textPrimary: AppTheme.textPrimaryDark,
  textSecondary: AppTheme.textSecondaryDark,
  primaryGreen: Color.fromARGB(255, 110, 188, 118),
  lightGreenBackground: AppTheme.primaryGreen,
  amberBackground: AppTheme.darkAmberBackground,
  buttonDark: AppTheme.buttonLight,
  dividerColor: AppTheme.dividerColorDark,
  surface: AppTheme.surfaceDark,
  textInverse: AppTheme.textPrimary,
);
const _sidebarSelectionFill = Color.fromARGB(255, 110, 188, 118);
const _sidebarOnSelection = Color(0xFF16301B);

class _Sidebar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;

  const _Sidebar({
    required this.selectedIndex,
    required this.onItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    const colors = _sidebarColors;
    return Container(
      width: 236,
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(right: BorderSide(color: colors.dividerColor)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 22),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: Image.asset(
                        'assets/app_icon_source.png',
                        width: 26,
                        height: 26,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Echo',
                      style: GoogleFonts.oldStandardTt(
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              // Ask Echo isn't a sidebar tab — it lives inside Today (the home
              // ask bar opens it inline), so Today stays selected while chatting.
              _SidebarItem(
                icon: Icons.home_rounded,
                label: 'Today',
                selected: selectedIndex == 0,
                onTap: () => onItemSelected(0),
              ),
              _SidebarItem(
                icon: Icons.inbox_rounded,
                label: 'The Vault',
                selected: selectedIndex == 1,
                onTap: () => onItemSelected(1),
              ),
              _SidebarItem(
                icon: Icons.person_rounded,
                label: 'Profile',
                selected: selectedIndex == 2,
                onTap: () => onItemSelected(2),
              ),
              const Spacer(),
              const _EngineStatus(),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const colors = _sidebarColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Pressable(
        onTap: onTap,
        pressedScale: 0.97,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: selected ? _sidebarSelectionFill : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected ? _sidebarOnSelection : colors.textSecondary,
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: GoogleFonts.nunito(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? _sidebarOnSelection : colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows whether this machine's optional Echo Engine is running, sourced
/// from the same setting Settings > "This Computer" controls.
class _EngineStatus extends StatelessWidget {
  const _EngineStatus();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        final on = state.runDesktopEngineHere;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.dividerColor),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on ? colors.primaryGreen : colors.textSecondary,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  on ? 'Echo Engine running' : 'Echo Engine off',
                  style: GoogleFonts.nunito(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
