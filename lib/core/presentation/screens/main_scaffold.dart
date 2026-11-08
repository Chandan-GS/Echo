import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/presentation/animations/fade_indexed_stack.dart';
import 'package:project_echo/core/presentation/widgets/nav_dock.dart';
import 'package:project_echo/features/desktop/presentation/desktop_workspace.dart';
import 'package:project_echo/features/echo/presentation/screens/today_screen.dart';
import 'package:project_echo/features/history/presentation/screens/history_screen.dart';
import 'package:project_echo/features/people/presentation/screens/people_screen.dart';
import 'package:project_echo/features/profile/presentation/screens/you_screen.dart';
import 'package:project_echo/demo/demo_mode.dart';
import 'package:project_echo/core/presentation/widgets/echo_bubble.dart';
import 'package:project_echo/core/services/echo_says.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MainScaffold extends StatefulWidget {
  final Widget child;

  const MainScaffold({super.key, required this.child});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;

  /// Tabs the owner has opened. A tab is built the first time it's shown, then
  /// kept, so launching doesn't load all four at once.
  final _visited = <int>{0};

  /// The tab screens, built once so a rebuild here doesn't rebuild them.
  final _tabs = const <Widget>[
    TodayScreen(),
    PeopleScreen(),
    HistoryScreen(),
    YouScreen(),
  ];

  // Phone only — the nav dock is the Ask Echo bar.
  bool _asking = false;

  /// Whether a tap on the briefing's notification or widget was last seen
  /// waiting, so each tap only moves the owner once.
  bool _autoplayPending = false;

  @override
  void initState() {
    super.initState();
    _selectedIndex = 0;
    if (!_desktop) {
      WidgetsBinding.instance.addObserver(this);
      // A cold start from that tap already opens on Today.
      unawaited(_followBriefingTap(navigate: false));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTabToRoute(context);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_followBriefingTap());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// A tap on the briefing's notification or widget is written as a flag by
  /// native code or a background isolate, and Today plays it. If the owner
  /// was somewhere else in the app, this brings them there.
  Future<void> _followBriefingTap({bool navigate = true}) async {
    // The tap's handler may still be writing the flag as the app resumes.
    if (navigate) await Future<void>.delayed(const Duration(milliseconds: 400));
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final pending = prefs.getBool('pending_autoplay') ?? false;
    final fresh = pending && !_autoplayPending;
    _autoplayPending = pending;
    if (fresh && navigate && mounted) context.go('/echo');
  }

  static bool get _desktop => Platform.isMacOS || Platform.isWindows;

  /// Each phone tab's route, in order. The desktop has its own sections
  /// (see DesktopWorkspace) and stays on '/echo'.
  static const _tabRoutes = ['/echo', '/people', '/history', '/profile'];

  /// Follows the route to its tab. Pushed screens leave the tab as it was,
  /// so back lands where the owner came from.
  void _syncTabToRoute(BuildContext context) {
    final i = _tabRoutes.indexOf(GoRouterState.of(context).uri.path);
    if (i < 0 || i == _selectedIndex) return;
    _selectedIndex = i;
    _visited.add(i);
    _asking = false;
  }

  void _onItemTapped(int index) {
    if (index == _selectedIndex) return;

    HapticFeedback.selectionClick();
    setState(() {
      _selectedIndex = index;
      _visited.add(index);
    });

    _updateRoute(index);
  }

  void _updateRoute(int index) => context.go(_tabRoutes[index]);

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
    _syncTabToRoute(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        // go_router's shell Navigator. The tabs below are drawn here, not
        // by its (empty) pages, but it has to be mounted: back presses and
        // pops look it up, and without it system back quits the app.
        Offstage(child: widget.child),
        _shell(context),
      ],
    );
  }

  Widget _shell(BuildContext context) {
    return _desktop
        // The filming build can open on Ask Echo (ECHO_ASK="a question").
        ? DesktopWorkspace(
            initialQuestion: kEchoDemo
                ? Platform.environment['ECHO_ASK']
                : null,
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
    // Echo keeps quiet while the question bar or keyboard is up.
    final quiet = _asking || keyboard > 0;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => EchoSays.instance.setQuiet(quiet),
    );

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
                // Scrolling moves Echo's ambient remarks out of the way.
                child: NotificationListener<ScrollUpdateNotification>(
                  onNotification: (_) {
                    EchoSays.instance.scrolled();
                    return false;
                  },
                  child: FadeIndexedStack(
                    index: _selectedIndex,
                    children: [
                      for (var i = 0; i < _tabs.length; i++)
                        if (_visited.contains(i))
                          _tabs[i]
                        else
                          const SizedBox.shrink(),
                    ],
                  ),
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
            // What Echo says, resting on the dock and as wide as it.
            Positioned(
              left: 20,
              right: 20,
              // The tail's tip just meets the dock, above Echo.
              bottom: dockBottom + kNavDockHeight + 1,
              child: const EchoBubble(),
            ),
            // Invisible: it only listens. Positioned, so the Stack doesn't
            // take its zero size as the size of the whole screen.
            Positioned(
              left: 0,
              top: 0,
              child: EchoSaysHost(onOpenHome: () => _onItemTapped(0)),
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
