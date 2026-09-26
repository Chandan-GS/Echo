import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/presentation/animations/fade_indexed_stack.dart';
import 'package:project_echo/core/presentation/widgets/animated_nav_icons.dart';
import 'package:project_echo/core/presentation/screens/desktop_shell.dart';
import 'package:project_echo/features/echo/presentation/cubit/briefing_cubit.dart';
import 'package:project_echo/features/todo/presentation/cubit/todo_cubit.dart';
import 'package:project_echo/features/echo/presentation/screens/echo_home_screen.dart';
import 'package:project_echo/features/echo/presentation/screens/desktop_home_screen.dart';
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

  // Desktop only — whether the sidebar's persistent "Ask Echo" tab is
  // showing. Deliberately not route-driven (unlike _selectedIndex): Ask Echo
  // has no route of its own here, so route-based auto-sync would never
  // select it and would stomp it back off on the next rebuild.
  bool _desktopAskEchoActive = false;

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

  // Desktop only — selecting Today/Vault/Profile always leaves the inline Ask
  // Echo chat, so the tapped tab is revealed even when its route index hasn't
  // changed.
  void _onDesktopItemSelected(int index) {
    if (_desktopAskEchoActive) {
      setState(() => _desktopAskEchoActive = false);
    }
    _onItemTapped(index);
  }

  // Desktop only — the inline Ask Echo chat lives inside the Today pane, so
  // opening it means selecting Today first, then flipping the chat on.
  void _openHomeChat() {
    HapticFeedback.selectionClick();
    if (_selectedIndex != 0) {
      setState(() => _selectedIndex = 0);
      context.go('/echo');
    }
    setState(() => _desktopAskEchoActive = true);
  }

  void _closeHomeChat() => setState(() => _desktopAskEchoActive = false);

  @override
  Widget build(BuildContext context) {
    final routeIndex = _calculateSelectedIndex(context);
    if (routeIndex != _selectedIndex) {
      _selectedIndex = routeIndex;
    }

    // BriefingCubit is provided here (above the tabs) rather than inside
    // EchoHomeScreen so a briefing keeps generating across tab switches and can
    // never be torn down by incidental navigation — and so the whole shell can
    // surface a "working in background" indicator.
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => BriefingCubit()),
        // The to-do list lives beside the briefing: home shows it, the
        // briefing screen can make or update it.
        BlocProvider(create: (_) => TodoCubit()),
      ],
      child: (Platform.isMacOS || Platform.isWindows)
          ? DesktopShell(
              selectedIndex: _selectedIndex,
              onItemSelected: _onDesktopItemSelected,
              content: FadeIndexedStack(
                index: _selectedIndex,
                children: [
                  DesktopHomeScreen(
                    chatActive: _desktopAskEchoActive,
                    onOpenChat: _openHomeChat,
                    onCloseChat: _closeHomeChat,
                    onOpenSettings: () => _onDesktopItemSelected(2),
                  ),
                  const VaultScreen(),
                  const SettingsScreen(),
                ],
              ),
            )
          : Scaffold(
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
                  // Floating "generating in background" pill — shown on any tab other
                  // than Today (which already shows the full generating view). Tap to
                  // jump back to the briefing.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 140,
                    child: BlocBuilder<BriefingCubit, BriefingState>(
                      builder: (context, state) {
                        final show =
                            state is BriefingGenerating && _selectedIndex != 0;
                        return AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: show
                              ? Center(
                                  child: _GeneratingPill(
                                    onTap: () => _onItemTapped(0),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        );
                      },
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

/// A small breathing dot used to signal ongoing background work.
class _PulseDot extends StatefulWidget {
  final Color? color;
  const _PulseDot({this.color});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.colors.primaryGreen;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1.0).animate(_c),
      child: Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// Floating "working in the background" chip shown while a briefing generates
/// and the user is on another tab. Tapping it returns to the briefing.
class _GeneratingPill extends StatelessWidget {
  final VoidCallback onTap;
  const _GeneratingPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final onSel = context.onSelection;
    return Material(
      color: context.selectionFill,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PulseDot(color: onSel),
              const SizedBox(width: 10),
              Text(
                'Preparing your briefing…',
                style: GoogleFonts.nunito(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: onSel,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
