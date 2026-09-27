import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/presentation/animations/fade_indexed_stack.dart';
import 'package:project_echo/core/presentation/widgets/nav_dock.dart';
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

  // Phone only — the nav dock is the Ask Echo bar.
  bool _asking = false;

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

  void _openAsk() {
    HapticFeedback.lightImpact();
    setState(() => _asking = true);
  }

  void _closeAsk() => setState(() => _asking = false);

  void _ask(String question) {
    _closeAsk();
    context.push('/echo/chat', extra: question);
  }

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
      child: Stack(
        fit: StackFit.expand,
        children: [
          // go_router's shell Navigator. The tabs below are drawn here, not
          // by its (empty) pages, but it has to be mounted: back presses and
          // pops look it up, and without it system back quits the app.
          Offstage(child: widget.child),
          _shell(context),
        ],
      ),
    );
  }

  Widget _shell(BuildContext context) {
    return (Platform.isMacOS || Platform.isWindows)
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
        : _phone(context);
  }

  Widget _phone(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final systemBar = media.viewPadding.bottom;
    // The dock floats a fixed gap above whatever Android has at the bottom
    // (gesture handle or three buttons), or above the keyboard while asking.
    final dockBottom = _asking && keyboard > 0 ? keyboard + 10 : systemBar + 12;
    // What the tabs keep clear at the bottom so nothing ends under the dock.
    final clearance = systemBar + 12 + kNavDockHeight + 12;
    const motion = Duration(milliseconds: 260);

    return PopScope(
      canPop: !_asking,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _asking) _closeAsk();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            // Full height: content scrolls behind the dock, and screens
            // pad their ends by MediaQuery's bottom padding (the clearance).
            Positioned.fill(
              child: MediaQuery(
                data: media.copyWith(
                  padding: media.padding.copyWith(bottom: clearance),
                ),
                child: FadeIndexedStack(
                  index: _selectedIndex,
                  children: const [
                    EchoHomeScreen(),
                    VaultScreen(),
                    SettingsScreen(),
                  ],
                ),
              ),
            ),
            // Content fades out under the dock instead of cutting off.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: clearance,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        context.colors.background,
                        context.colors.background.withValues(alpha: 0),
                      ],
                      stops: const [0.45, 1],
                    ),
                  ),
                ),
              ),
            ),
            // Floating "generating in background" pill — shown on any tab
            // other than Today (which already shows the full generating
            // view). Tap to jump back to the briefing.
            Positioned(
              left: 0,
              right: 0,
              bottom: clearance + 8,
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
            // Dims the screen behind the question bar; tap to close it.
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !_asking,
                child: AnimatedOpacity(
                  duration: motion,
                  opacity: _asking ? 1 : 0,
                  child: GestureDetector(
                    onTap: _closeAsk,
                    child: const ColoredBox(color: Color(0x73000000)),
                  ),
                ),
              ),
            ),
            AnimatedPositioned(
              duration: motion,
              curve: Curves.easeOutCubic,
              left: 0,
              right: 0,
              bottom: dockBottom + kNavDockHeight + 12,
              child: IgnorePointer(
                ignoring: !_asking,
                child: AnimatedOpacity(
                  duration: motion,
                  opacity: _asking ? 1 : 0,
                  child: AskSuggestionChips(
                    questions: kAskSuggestions,
                    onAsk: _ask,
                  ),
                ),
              ),
            ),
            AnimatedPositioned(
              duration: motion,
              curve: Curves.easeOutCubic,
              left: 20,
              right: 20,
              bottom: dockBottom,
              child: NavDock(
                selectedIndex: _selectedIndex,
                onTabSelected: _onItemTapped,
                asking: _asking,
                onOpenAsk: _openAsk,
                onCloseAsk: _closeAsk,
                onAsk: _ask,
              ),
            ),
          ],
        ),
      ),
    );
  }
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
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
