import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:project_echo/core/presentation/widgets/animated_nav_icons.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_mascot.dart';
import 'package:project_echo/core/services/echo_says.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/widgets/pressable.dart';

/// Height of the dock's pill and of Echo beside it.
const double kNavDockHeight = 56;

/// The phone's bottom navigation: the four tabs in one floating pill, and
/// Echo beside it as the way to ask him something. Tapping Echo turns the dock
/// into the question bar — the tabs fold into a close button and Echo grows
/// into a text field.
class NavDock extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final bool asking;
  final VoidCallback onOpenAsk;
  final VoidCallback onCloseAsk;
  final ValueChanged<String> onAsk;

  const NavDock({
    super.key,
    required this.selectedIndex,
    required this.onTabSelected,
    required this.asking,
    required this.onOpenAsk,
    required this.onCloseAsk,
    required this.onAsk,
  });

  @override
  State<NavDock> createState() => _NavDockState();
}

class _NavDockState extends State<NavDock> {
  static const _tabItems = [
    (Symbols.home_rounded, Symbols.home_rounded, 'Home'),
    (Symbols.checklist_rounded, Symbols.checklist_rounded, 'To-do'),
    (Symbols.inbox_rounded, Symbols.inbox_rounded, 'Vault'),
    (Symbols.person_rounded, Symbols.person_rounded, 'Profile'),
  ];

  /// Each tab's width: roomy on most phones, narrower on small ones so the
  /// pill and Echo always fit side by side.
  static const _maxTabWidth = 66.0;
  static const _minTabWidth = 52.0;
  static const _gap = 16.0;
  static const _pillPadding = 6.0;
  static const _motion = Duration(milliseconds: 380);
  static const _curve = Cubic(0.3, 1.15, 0.4, 1);

  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void didUpdateWidget(covariant NavDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.asking && !oldWidget.asking) {
      // Once the bar has room for the field.
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted && widget.asking) _focus.requestFocus();
      });
    } else if (!widget.asking && oldWidget.asking) {
      _focus.unfocus();
      _controller.clear();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Sends the question; with nothing typed, opens Ask Echo itself, which
  /// leads with what's come in for the owner.
  void _submit() => widget.onAsk(_controller.text.trim());

  /// Light mode only: a soft, wide shadow that melts into the page. In dark
  /// mode the dock holds its edge with the hairline alone.
  List<BoxShadow>? _shadow(BuildContext context) => context.isDarkMode
      ? null
      : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 32,
            spreadRadius: -6,
            offset: const Offset(0, 10),
          ),
        ];

  /// The dock's own surface: white in light mode, dark in dark mode, with a
  /// hairline so it holds its edge against the page.
  BoxDecoration _surface(BuildContext context) => BoxDecoration(
    color: context.colors.surface,
    borderRadius: BorderRadius.circular(kNavDockHeight / 2),
    border: Border.all(
      color: context.colors.dividerColor.withValues(
        alpha: context.isDarkMode ? 0.9 : 0.6,
      ),
    ),
    boxShadow: _shadow(context),
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // One springy value drives both widths, so the pill folding and the
        // bar growing always add up to the space — the overshoot is clamped.
        return TweenAnimationBuilder<double>(
          tween: Tween(end: widget.asking ? 1 : 0),
          duration: _motion,
          curve: _curve,
          builder: (context, t, _) {
            final full = constraints.maxWidth;
            final tabWidth =
                ((full - kNavDockHeight - _gap - _pillPadding * 2) /
                        _tabItems.length)
                    .clamp(_minTabWidth, _maxTabWidth);
            final tabsWidth = tabWidth * _tabItems.length + _pillPadding * 2;
            final tabsW = lerpDouble(
              tabsWidth,
              kNavDockHeight,
              t,
            )!.clamp(kNavDockHeight, tabsWidth);
            final echoW = lerpDouble(
              kNavDockHeight,
              full - kNavDockHeight - _gap,
              t,
            )!.clamp(kNavDockHeight, full - tabsW - _gap);
            return SizedBox(
              height: kNavDockHeight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: tabsW,
                    child: _tabs(context, tabWidth, tabsWidth),
                  ),
                  const SizedBox(width: _gap),
                  SizedBox(width: echoW, child: _echo(context, t)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _tabs(BuildContext context, double tabWidth, double tabsWidth) {
    final c = context.colors;
    return Container(
      height: kNavDockHeight,
      decoration: _surface(context),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // The tabs keep their full width and are clipped as the pill folds.
          IgnorePointer(
            ignoring: widget.asking,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 160),
              opacity: widget.asking ? 0 : 1,
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: tabsWidth,
                maxWidth: tabsWidth,
                child: Padding(
                  padding: const EdgeInsets.all(_pillPadding),
                  child: Stack(
                    children: [
                      _StretchPill(
                        index: widget.selectedIndex,
                        tabWidth: tabWidth,
                        color: c.primaryGreen,
                      ),
                      Row(
                        children: [
                          for (final (i, (off, on, label)) in _tabItems.indexed)
                            Semantics(
                              button: true,
                              selected: widget.selectedIndex == i,
                              label: label,
                              child: Pressable(
                                scale: 0.88,
                                haptic: false,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => widget.onTabSelected(i),
                                  child: SizedBox(
                                    width: tabWidth,
                                    height: kNavDockHeight - _pillPadding * 2,
                                    child: Center(
                                      child: SquashInIcon(
                                        isSelected: widget.selectedIndex == i,
                                        selectedIcon: on,
                                        unselectedIcon: off,
                                        // Black on the green in dark mode,
                                        // white in light.
                                        color: widget.selectedIndex == i
                                            ? (context.isDarkMode
                                                  ? c.textInverse
                                                  : Colors.white)
                                            : c.textSecondary,
                                        size: 24,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Folded: the pill is a close button.
          IgnorePointer(
            ignoring: !widget.asking,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: widget.asking ? 1 : 0,
              child: Semantics(
                button: true,
                label: 'Close',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onCloseAsk,
                  child: SizedBox(
                    width: kNavDockHeight,
                    height: kNavDockHeight,
                    child: Icon(
                      Symbols.close_rounded,
                      size: 22,
                      color: c.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Echo on his own at rest — the whole button is the mascot. While asking
  /// ([t] → 1) the bar fades in behind him and he settles to its left.
  Widget _echo(BuildContext context, double t) {
    final c = context.colors;
    final bar = t.clamp(0.0, 1.0);
    // EchoMascot draws his body at 112/180 of its box (the rest is glow), so
    // he's drawn larger than his slot for the body itself to fill it.
    final body = lerpDouble(54, 42, bar)!;
    final canvas = body * 180 / 112;
    return Semantics(
      button: !widget.asking,
      label: widget.asking ? null : 'Ask Echo',
      child: Pressable(
        scale: 0.92,
        enabled: !widget.asking,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.asking ? null : widget.onOpenAsk,
          child: Stack(
            children: [
              Positioned.fill(
                child: Opacity(
                  opacity: bar,
                  child: DecoratedBox(decoration: _surface(context)),
                ),
              ),
              LayoutBuilder(
                builder: (context, box) {
                  // The field and send button only once there's room for them.
                  final open = widget.asking && box.maxWidth > 150;
                  return SizedBox(
                    height: kNavDockHeight,
                    child: Row(
                      children: [
                        SizedBox(width: lerpDouble(1, 7, bar)),
                        SizedBox(
                          width: body,
                          height: kNavDockHeight,
                          child: OverflowBox(
                            maxWidth: canvas,
                            maxHeight: canvas,
                            child: IgnorePointer(
                              // His face matches what he's saying, if anything.
                              child: ValueListenableBuilder<EchoLine?>(
                                valueListenable: EchoSays.instance.current,
                                builder: (context, line, _) => EchoMascot(
                                  state: line?.mood ?? EchoState.idle,
                                  size: canvas,
                                  showRings: false,
                                  glow: false,
                                  followTouchAnywhere: true,
                                  gazeReach: 2.2,
                                  gazeReachY: 4,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (open) ...[
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              focusNode: _focus,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _submit(),
                              cursorColor: c.primaryGreen,
                              style: GoogleFonts.nunito(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w600,
                                color: c.textPrimary,
                              ),
                              decoration: InputDecoration(
                                isCollapsed: true,
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                hintText: 'Ask Echo anything',
                                hintStyle: GoogleFonts.nunito(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w600,
                                  color: c.textSecondary,
                                ),
                              ),
                            ),
                          ),
                          Semantics(
                            button: true,
                            label: 'Send',
                            child: Pressable(
                              scale: 0.88,
                              child: GestureDetector(
                                onTap: _submit,
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: c.primaryGreen,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Symbols.arrow_upward_rounded,
                                    size: 24,
                                    color: context.isDarkMode
                                        ? c.textInverse
                                        : Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ready-made questions shown above the question bar. Deliberately general:
/// they work on any day, whatever came in.
const kAskSuggestions = [
  'What did I miss today?',
  'Anything urgent?',
  "What's on tomorrow?",
  'Who should I reply to?',
];

/// Ready-made questions shown above the question bar.
class AskSuggestionChips extends StatelessWidget {
  final List<String> questions;
  final ValueChanged<String> onAsk;

  const AskSuggestionChips({
    super.key,
    required this.questions,
    required this.onAsk,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: questions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) => Pressable(
          child: Material(
            color: c.surface,
            shape: StadiumBorder(
              side: BorderSide(color: c.dividerColor.withValues(alpha: 0.8)),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onAsk(questions[i]),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Center(
                  child: Text(
                    questions[i],
                    style: GoogleFonts.nunito(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The green pill under the chosen tab. Moving to another tab it stretches:
/// the edge on the way leaves first and the other catches up, like a drop
/// of liquid, then it settles to one tab wide.
class _StretchPill extends StatefulWidget {
  final int index;
  final double tabWidth;
  final Color color;

  const _StretchPill({
    required this.index,
    required this.tabWidth,
    required this.color,
  });

  @override
  State<_StretchPill> createState() => _StretchPillState();
}

class _StretchPillState extends State<_StretchPill> {
  static const _lead = Duration(milliseconds: 240);
  static const _trail = Duration(milliseconds: 420);
  static const _curve = Cubic(0.3, 1.2, 0.4, 1);

  /// Which way it last moved: right (to a later tab) or left.
  bool _right = true;

  @override
  void didUpdateWidget(_StretchPill old) {
    super.didUpdateWidget(old);
    if (widget.index != old.index) _right = widget.index > old.index;
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.index * widget.tabWidth;
    final right = left + widget.tabWidth;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: left),
      duration: _right ? _trail : _lead,
      curve: _curve,
      builder: (context, l, _) => TweenAnimationBuilder<double>(
        tween: Tween(end: right),
        duration: _right ? _lead : _trail,
        curve: _curve,
        builder: (context, r, _) => Positioned(
          left: l,
          top: 0,
          bottom: 0,
          // The overshoot can briefly cross the edges; never inside out.
          width: (r - l).clamp(widget.tabWidth * 0.6, double.infinity),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: BorderRadius.circular(22),
            ),
          ),
        ),
      ),
    );
  }
}
