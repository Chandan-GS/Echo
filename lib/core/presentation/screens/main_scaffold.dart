import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/presentation/animations/fade_indexed_stack.dart';
import 'package:project_echo/core/presentation/widgets/animated_nav_icons.dart';
import 'package:project_echo/features/echo/presentation/screens/echo_home_screen.dart';
import 'package:project_echo/features/vault/presentation/screens/vault_screen.dart';
import 'package:project_echo/features/settings/presentation/screens/settings_screen.dart';

class MainScaffold extends StatefulWidget {
  final Widget child;

  const MainScaffold({super.key, required this.child});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _selectedIndex = 0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final routeIndex = _calculateSelectedIndex(context);
    if (routeIndex != _selectedIndex) {
      _selectedIndex = routeIndex;
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  static int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/echo')) {
      return 0;
    }
    if (location.startsWith('/vault')) {
      return 1;
    }
    if (location.startsWith('/profile')) {
      return 2;
    }
    return 0;
  }

  void _onItemTapped(int index) {
    if (index == _selectedIndex) return;

    HapticFeedback.selectionClick();
    setState(() {
      _selectedIndex = index;
    });

    _updateRoute(index);
  }

  void _updateRoute(int index) {
    switch (index) {
      case 0:
        context.go('/echo');
        break;
      case 1:
        context.go('/vault');
        break;
      case 2:
        context.go('/profile');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final routeIndex = _calculateSelectedIndex(context);
    if (routeIndex != _selectedIndex) {
      _selectedIndex = routeIndex;
    }

    return Scaffold(
      body: Stack(
        children: [
          // Persistent screen area using IndexedStack to prevent rebuild jitter
          Positioned.fill(
            bottom: 80,
            child: FadeIndexedStack(
              index: _selectedIndex,
              children: const [
                EchoHomeScreen(),
                VaultScreen(),
                SettingsScreen(),
              ],
            ),
          ),
          // Floating Capsule Nav Bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 20,
            child: Center(
              child: _FloatingNavBar(
                selectedIndex: _selectedIndex,
                onItemSelected: _onItemTapped,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;

  const _FloatingNavBar({
    required this.selectedIndex,
    required this.onItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      _NavBarItem(
        label: 'Today',
        iconBuilder: (isSelected, color) => BounceInIcon(
          isSelected: isSelected,
          selectedIcon: Icons.home_rounded,
          unselectedIcon: Icons.home_outlined,
          color: color,
          size: 26,
        ),
      ),
      _NavBarItem(
        label: 'Vault',
        iconBuilder: (isSelected, color) => BounceInIcon(
          isSelected: isSelected,
          selectedIcon: Icons.inbox,
          unselectedIcon: Icons.inbox_outlined,
          color: color,
          size: 26,
        ),
      ),
      _NavBarItem(
        label: 'Profile',
        iconBuilder: (isSelected, color) => BounceInIcon(
          isSelected: isSelected,
          selectedIcon: Icons.person,
          unselectedIcon: Icons.person_outline,
          color: color,
          size: 26,
        ),
      ),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(34),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 0.0, vertical: 8),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 10),
          height: 68,
          width: double.infinity,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(34)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
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
                      top: 8,
                      bottom: 8,
                      width: itemWidth,
                      child: Container(
                        margin: EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: context.colors.lightGreenBackground,
                          borderRadius: BorderRadius.circular(26),
                        ),
                      ),
                    ),
                    // Nav Items Row
                    Row(
                      children: List.generate(items.length, (index) {
                        final item = items[index];
                        final isSelected = selectedIndex == index;

                        return Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => onItemSelected(index),
                            child: Center(
                              child: AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 250),
                                style: GoogleFonts.nunito(
                                  fontSize: 11,
                                  fontWeight: isSelected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: context.colors.textPrimary,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    item.iconBuilder(
                                      isSelected,
                                      context.colors.textPrimary,
                                    ),
                                  ],
                                ),
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
          ),
        ),
      ),
    );
  }
}

class _NavBarItem {
  final String label;
  final Widget Function(bool isSelected, Color color) iconBuilder;

  _NavBarItem({required this.label, required this.iconBuilder});
}
