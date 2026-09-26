import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/core/presentation/animations/fade_slide_in.dart';
import 'package:project_echo/core/presentation/widgets/echo_app_bar.dart';
import 'package:project_echo/core/services/home_widgets_service.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/todo/presentation/cubit/todo_cubit.dart';
import 'package:project_echo/features/widgets/presentation/widgets/widget_previews.dart';

class _Kind {
  final String id, name, size, description;
  final bool wide;
  const _Kind(
    this.id,
    this.name,
    this.size,
    this.description, {
    this.wide = false,
  });
}

const _kinds = [
  _Kind(
    'todo',
    'Echo To-do',
    '4 × 3',
    "Today's to-dos from your briefing. Tick them off right on your home screen.",
    wide: true,
  ),
  _Kind(
    'ring',
    'Echo To-do Progress',
    '2 × 2',
    "How much of today is done, and what's next.",
  ),
  _Kind(
    'brief',
    'Echo Briefing',
    '4 × 2',
    "Your streak and this week at a glance. Tap to play today's briefing.",
    wide: true,
  ),
  _Kind(
    'streak',
    'Echo Streak',
    '2 × 2',
    'Your streak, big and bold, with when the next briefing is ready.',
  ),
];

/// Profile → Widgets: previews of Echo's home-screen widgets with a way to
/// add each one. Adding asks Android to pin it; the widget lifts out of its
/// card and flies up out of the app, Android confirms, and the launcher
/// places it. On return Echo recounts what's placed.
class WidgetsScreen extends StatefulWidget {
  const WidgetsScreen({super.key});

  @override
  State<WidgetsScreen> createState() => _WidgetsScreenState();
}

class _WidgetsScreenState extends State<WidgetsScreen>
    with TickerProviderStateMixin {
  HomeWidgetsState? _state;
  final _previewKeys = {for (final k in _kinds) k.id: GlobalKey()};
  final Set<String> _howTo = {};

  /// The widget currently away from its card (flying, or with Android).
  String? _away;
  int _awayCountBefore = 0;

  /// Widgets that were just placed, for the tick animation.
  final Set<String> _justPlaced = {};

  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    _refresh();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final s = await HomeWidgetsService.state();
    if (mounted) setState(() => _state = s);
  }

  /// Back from Android's confirmation: did the widget land? The launcher can
  /// take a moment to bind it, so look a few times before giving up.
  Future<void> _onResume() async {
    final kind = _away;
    if (kind == null) {
      _refresh();
      return;
    }
    for (var attempt = 0; attempt < 6; attempt++) {
      final s = await HomeWidgetsService.state();
      if (!mounted) return;
      if (s != null && s.placedCount(kind) > _awayCountBefore) {
        HapticFeedback.mediumImpact();
        setState(() {
          _state = s;
          _away = null;
          _justPlaced.add(kind);
        });
        final name = _kinds.firstWhere((k) => k.id == kind).name;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$name is on your home screen'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    // Cancelled (or the launcher never placed it): bring the preview back.
    if (mounted) setState(() => _away = null);
  }

  Future<void> _add(_Kind kind) async {
    HapticFeedback.lightImpact();
    final s = _state;
    if (s == null || !s.canPin) {
      setState(
        () => _howTo.contains(kind.id)
            ? _howTo.remove(kind.id)
            : _howTo.add(kind.id),
      );
      return;
    }
    if (_away != null) return;
    _awayCountBefore = s.placedCount(kind.id);
    await _flyAway(kind);
    final asked = await HomeWidgetsService.pin(kind.id);
    if (!asked && mounted) {
      setState(() {
        _away = null;
        _howTo.add(kind.id);
      });
    }
  }

  /// A copy of the preview lifts out of its card and flies up out of the app.
  Future<void> _flyAway(_Kind kind) async {
    final box =
        _previewKeys[kind.id]!.currentContext?.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context);
    if (box == null || !box.attached) {
      setState(() => _away = kind.id);
      return;
    }
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final screen = MediaQuery.of(context).size;
    final preview = _preview(kind);
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 760),
    );
    final entry = OverlayEntry(
      builder: (_) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final t = controller.value;
          final lift = Curves.easeOut.transform((t / 0.28).clamp(0.0, 1.0));
          final fly = Cubic(
            0.45,
            0,
            0.2,
            1,
          ).transform(((t - 0.28) / 0.72).clamp(0.0, 1.0));
          final dx = (screen.width / 2 - rect.center.dx) * fly;
          final dy = -8 * lift + (-rect.bottom - rect.height * 0.2) * fly;
          final scale = (1 + 0.05 * lift) * (1 - 0.66 * fly);
          return Positioned(
            left: rect.left,
            top: rect.top,
            width: rect.width,
            height: rect.height,
            child: IgnorePointer(
              child: Opacity(
                opacity: 1 - 0.8 * fly,
                child: Transform.translate(
                  offset: Offset(dx, dy),
                  child: Transform.rotate(
                    angle: -6 * math.pi / 180 * fly,
                    child: Transform.scale(
                      scale: scale,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: 0.35 * lift * (1 - fly),
                              ),
                              blurRadius: 24,
                              offset: const Offset(0, 18),
                            ),
                          ],
                        ),
                        child: FittedBox(child: preview),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    setState(() => _away = kind.id);
    overlay.insert(entry);
    await controller.forward();
    entry.remove();
    controller.dispose();
  }

  Widget _preview(_Kind kind) {
    final todo = context.read<TodoCubit>().state;
    return switch (kind.id) {
      'todo' => TodoWidgetPreview(todo: todo),
      'ring' => RingWidgetPreview(todo: todo),
      'brief' => BriefingWidgetPreview(data: _state),
      _ => StreakWidgetPreview(data: _state),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: const EchoAppBar(title: 'Widgets'),
      body: BlocBuilder<TodoCubit, TodoState>(
        builder: (context, _) => ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(22, 6, 22, 48),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 0, 2, 18),
              child: Text(
                'Keep Echo on your home screen. These show your live data and update on their own.',
                style: GoogleFonts.nunito(
                  fontSize: 14.5,
                  color: context.colors.textSecondary,
                ),
              ),
            ),
            for (var i = 0; i < _kinds.length; i++)
              FadeSlideIn(
                delay: Duration(milliseconds: 60 * i),
                child: _card(context, _kinds[i]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _card(BuildContext context, _Kind kind) {
    final c = context.colors;
    final placed = (_state?.placedCount(kind.id) ?? 0) > 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: c.dividerColor.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The widget, shown on a small wallpaper as it would sit on the
          // home screen.
          Container(
            constraints: const BoxConstraints(minHeight: 170),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.6, -1),
                radius: 1.4,
                colors: [
                  Color(0xFF4C6A52),
                  Color(0xFF243A2B),
                  Color(0xFF141D16),
                ],
                stops: [0, 0.5, 1],
              ),
            ),
            alignment: Alignment.center,
            child: AnimatedOpacity(
              opacity: _away == kind.id ? 0 : 1,
              duration: const Duration(milliseconds: 220),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Transform.scale(
                  scale: kind.wide ? 0.95 : 1,
                  child: KeyedSubtree(
                    key: _previewKeys[kind.id],
                    child: _preview(kind),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      kind.name,
                      style: GoogleFonts.nunito(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      kind.size,
                      style: GoogleFonts.nunito(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  kind.description,
                  style: GoogleFonts.nunito(
                    fontSize: 13.5,
                    color: c.textSecondary,
                  ),
                ),
                const SizedBox(height: 14),
                if (placed)
                  Row(
                    children: [
                      _PlacedTick(animate: _justPlaced.contains(kind.id)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'On your home screen',
                          style: GoogleFonts.nunito(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: c.primaryGreen,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _add(kind),
                        style: TextButton.styleFrom(
                          foregroundColor: c.textSecondary,
                        ),
                        child: Text(
                          'Add another',
                          style: GoogleFonts.nunito(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  Material(
                    color: c.textPrimary,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _add(kind),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_to_home_screen_rounded,
                              size: 20,
                              color: c.textInverse,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Add to home screen',
                              style: GoogleFonts.nunito(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                color: c.textInverse,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  child: _howTo.contains(kind.id)
                      ? _HowTo(name: kind.name)
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A green tick that pops in and draws itself when a widget has just landed.
class _PlacedTick extends StatelessWidget {
  final bool animate;
  const _PlacedTick({required this.animate});

  @override
  Widget build(BuildContext context) {
    final green = context.colors.primaryGreen;
    Widget tick(double pop, double draw) => Transform.scale(
      scale: pop,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(color: green, shape: BoxShape.circle),
        child: CustomPaint(painter: _TickPainter(draw, context.colors.surface)),
      ),
    );
    if (!animate) return tick(1, 1);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      builder: (context, t, _) => tick(
        const Cubic(0.34, 1.56, 0.64, 1).transform((t / 0.6).clamp(0.0, 1.0)),
        Curves.easeOut.transform(((t - 0.35) / 0.65).clamp(0.0, 1.0)),
      ),
    );
  }
}

class _TickPainter extends CustomPainter {
  final double t;
  final Color color;
  _TickPainter(this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * 0.28, h * 0.52)
      ..lineTo(w * 0.44, h * 0.67)
      ..lineTo(w * 0.72, h * 0.36);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * t),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _TickPainter old) =>
      old.t != t || old.color != color;
}

/// For launchers that don't let apps add widgets.
class _HowTo extends StatelessWidget {
  final String name;
  const _HowTo({required this.name});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final steps = [
      'Touch & hold an empty spot on your home screen',
      'Tap Widgets, then find Echo',
      'Drag $name to where you want it',
    ];
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.primaryGreen.withValues(
          alpha: context.isDarkMode ? 0.14 : 0.10,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Your launcher doesn't let apps add widgets. Add it by hand:",
            style: GoogleFonts.nunito(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                '${i + 1}. ${steps[i]}',
                style: GoogleFonts.nunito(
                  fontSize: 13.5,
                  color: c.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
