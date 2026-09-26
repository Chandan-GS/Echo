import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_echo/features/echo/presentation/cubit/briefing_cubit.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/services/widget_refresh_service.dart';
import 'package:project_echo/core/services/phone_sync_service.dart';
import 'package:project_echo/features/echo/presentation/screens/daily_briefing_screen.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/presentation/widgets/timer/next_briefing_strip.dart';
import 'package:project_echo/features/todo/presentation/cubit/todo_cubit.dart';
import 'package:project_echo/features/todo/presentation/widgets/todo_card.dart';
import 'package:project_echo/features/echo/presentation/widgets/generating_view.dart';
import 'package:project_echo/core/presentation/animations/page_transitions.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_mascot.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/presentation/animations/fade_slide_in.dart';

class EchoHomeScreen extends StatelessWidget {
  /// Desktop only — switches the shell to the persistent Ask Echo sidebar tab
  /// instead of pushing the phone's full-screen `/echo/chat` route. Null on
  /// phone, where the "Ask Echo" cards push the route as before.
  final VoidCallback? onAskEcho;

  const EchoHomeScreen({super.key, this.onAskEcho});

  @override
  Widget build(BuildContext context) {
    // BriefingCubit is provided by MainScaffold (app-scoped) so a briefing
    // keeps generating across tab switches; this screen just renders the view.
    return _EchoView(onAskEcho: onAskEcho);
  }
}

class _EchoView extends StatefulWidget {
  final VoidCallback? onAskEcho;
  const _EchoView({this.onAskEcho});

  @override
  State<_EchoView> createState() => _EchoViewState();
}

class _EchoViewState extends State<_EchoView> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Mirror this phone to a computer on the same Wi-Fi while the app is open.
    PhoneSyncService.instance.startPeriodic();
    PhoneSyncService.instance.syncNow();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PhoneSyncService.instance.stopPeriodic();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<BriefingCubit>().loadCachedBriefing();
      context.read<TodoCubit>().load();
      WidgetRefreshService.refresh();
      PhoneSyncService.instance.syncNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: context.colors.background,
      body: BlocConsumer<BriefingCubit, BriefingState>(
        listener: (context, state) async {
          if (state is BriefingReady) {
            // Read-and-clear the one-shot flag set when the user reached the
            // app via the notification's "Play" action (or by tapping it) —
            // see local_notification_service.dart / main.dart.
            final prefs = await SharedPreferences.getInstance();
            final autoPlay = prefs.getBool('pending_autoplay') ?? false;
            if (autoPlay) await prefs.remove('pending_autoplay');
            if (!context.mounted) return;

            Navigator.of(context, rootNavigator: true).push(
              bouncyRoute(
                DailyBriefingScreen(
                  rawText: state.rawText,
                  ttsText: state.ttsText,
                  autoPlay: autoPlay,
                  todoCubit: context.read<TodoCubit>(),
                  onReset: () {
                    context.read<BriefingCubit>().goBack();
                  },
                ),
              ),
            );
          }
        },
        builder: (context, state) {
          if (state is BriefingInitial) {
            return _InitialView(
              onGenerate: () =>
                  context.read<BriefingCubit>().generateBriefing(),
              onAskEcho: widget.onAskEcho,
            );
          }

          if (state is BriefingCached || state is BriefingReady) {
            final rawText = state is BriefingCached
                ? state.rawText
                : (state as BriefingReady).rawText;
            return _CachedView(
              onPlay: () =>
                  context.read<BriefingCubit>().playCachedBriefing(rawText),
              onRegenerate: () =>
                  context.read<BriefingCubit>().generateBriefing(),
              onAskEcho: widget.onAskEcho,
            );
          }

          if (state is BriefingGenerating) {
            return GeneratingView(partial: state.partial);
          }

          if (state is BriefingError) {
            return _ErrorView(
              message: state.message,
              onRetry: () => context.read<BriefingCubit>().generateBriefing(),
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Initial State — no briefing yet
// ---------------------------------------------------------------------------
class _InitialView extends StatelessWidget {
  final VoidCallback onGenerate;
  final VoidCallback? onAskEcho;
  const _InitialView({required this.onGenerate, this.onAskEcho});

  @override
  Widget build(BuildContext context) {
    return _HomeShell(
      subtitle: "Generate today's briefing to get started.",
      hasBriefing: false,
      primary: _ActionCard(
        title: 'Generate Briefing',
        subtitle: "Synthesize today's intelligence",
        icon: Icons.auto_awesome_rounded,
        onTap: onGenerate,
        isPrimary: true,
      ),
      secondary: Row(
        children: [
          Expanded(
            child: _QuickAction(
              label: 'Ask Echo',
              icon: Icons.chat_bubble_outline_rounded,
              onTap: onAskEcho ?? () => context.push('/echo/chat'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cached State — briefing exists for today
// ---------------------------------------------------------------------------
class _CachedView extends StatelessWidget {
  final VoidCallback onPlay;
  final VoidCallback onRegenerate;
  final VoidCallback? onAskEcho;
  const _CachedView({
    required this.onPlay,
    required this.onRegenerate,
    this.onAskEcho,
  });

  @override
  Widget build(BuildContext context) {
    return _HomeShell(
      subtitle: 'Your briefing is ready.',
      hasBriefing: true,
      primary: _ActionCard(
        title: "Play Today's Briefing",
        subtitle: 'Listen to the cached summary',
        icon: Icons.play_arrow_rounded,
        onTap: onPlay,
        isPrimary: true,
      ),
      secondary: Row(
        children: [
          Expanded(
            child: _QuickAction(
              label: 'Ask Echo',
              icon: Icons.chat_bubble_outline_rounded,
              onTap: onAskEcho ?? () => context.push('/echo/chat'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _QuickAction(
              label: 'Regenerate',
              icon: Icons.auto_awesome_rounded,
              onTap: onRegenerate,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error State
// ---------------------------------------------------------------------------
class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return _HomeShell(
      subtitle: "We couldn't generate your briefing.",
      hasBriefing: false,
      primary: _ActionCard(
        title: 'Try Again',
        subtitle: 'Attempt generation again',
        icon: Icons.refresh_rounded,
        onTap: onRetry,
        isPrimary: true,
      ),
      // Surface the raw reason quietly below, without a section heading.
      secondary: Text(
        message,
        textAlign: TextAlign.center,
        style: GoogleFonts.nunito(
          fontSize: 12.5,
          color: context.colors.textSecondary,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared shell (header + signal card + action list)
// ---------------------------------------------------------------------------
class _HomeShell extends StatefulWidget {
  /// One-line status under the greeting (state-dependent).
  final String subtitle;

  /// The single most important action for this state (Play / Generate / Retry).
  final Widget primary;

  /// Optional secondary actions (already laid out — a row or a single card).
  final Widget? secondary;

  /// Whether today's briefing exists (the to-do list is made from it).
  final bool hasBriefing;

  const _HomeShell({
    required this.subtitle,
    required this.primary,
    required this.hasBriefing,
    this.secondary,
  });

  @override
  State<_HomeShell> createState() => _HomeShellState();
}


class _HomeShellState extends State<_HomeShell> {
  String? _userName;

  @override
  void initState() {
    super.initState();
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _userName = prefs.getString('user_name');
        });
      }
    } catch (_) {}
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) {
      return 'Good morning';
    } else if (hour >= 12 && hour < 17) {
      return 'Good afternoon';
    } else if (hour >= 17 && hour < 22) {
      return 'Good evening';
    } else {
      return 'Good night';
    }
  }

  @override
  Widget build(BuildContext context) {
    final greeting = _getGreeting();
    final name = _userName ?? 'Sir';

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 128),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Hero: Echo beside the greeting, compact so the list sits
            // above the fold ────────────────────────────────────────────────
            FadeSlideIn(
              child: Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 20),
                child: Row(
                  children: [
                    const _HopOnArrival(
                      child: EchoMascot(state: EchoState.idle, size: 76),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$greeting,\n$name',
                            style: GoogleFonts.oldStandardTt(
                              fontSize: 27,
                              fontWeight: FontWeight.w700,
                              color: context.colors.textPrimary,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            widget.subtitle,
                            style: GoogleFonts.nunito(
                              fontSize: 14,
                              color: context.colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Primary action ────────────────────────────────────────────
            FadeSlideIn(
              delay: AppMotion.staggerDelay(1),
              child: widget.primary,
            ),

            // ── Secondary actions, always right under it ───────────────────
            if (widget.secondary != null) ...[
              const SizedBox(height: 10),
              FadeSlideIn(
                delay: AppMotion.staggerDelay(2),
                child: widget.secondary!,
              ),
            ],

            // ── Today's to-dos ────────────────────────────────────────────
            const SizedBox(height: 16),
            FadeSlideIn(
              delay: AppMotion.staggerDelay(3),
              child: TodoCard(hasBriefing: widget.hasBriefing),
            ),

            // ── Next briefing ─────────────────────────────────────────────
            const SizedBox(height: 16),
            FadeSlideIn(
              delay: AppMotion.staggerDelay(4),
              child: const NextBriefingStrip(),
            ),

            // ── Ambient stat ──────────────────────────────────────────────
            const SizedBox(height: 14),
            FadeSlideIn(
              delay: AppMotion.staggerDelay(5),
              child: FutureBuilder<List<RawData>>(
                future: IsarDataSource.getAllEntries(),
                builder: (context, snapshot) {
                  final count = snapshot.data?.length ?? 0;
                  return _SignalCard(signalCount: count);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Echo gives a little hop when a new to-do list lands.
class _HopOnArrival extends StatefulWidget {
  final Widget child;
  const _HopOnArrival({required this.child});

  @override
  State<_HopOnArrival> createState() => _HopOnArrivalState();
}

class _HopOnArrivalState extends State<_HopOnArrival>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  late final Animation<double> _lift = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: -12.0).chain(CurveTween(curve: Curves.easeOut)), weight: 30),
    TweenSequenceItem(tween: Tween(begin: -12.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)), weight: 30),
    TweenSequenceItem(tween: ConstantTween(0.0), weight: 40),
  ]).animate(_hop);

  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.06), weight: 30),
    TweenSequenceItem(tween: Tween(begin: 1.06, end: 0.97), weight: 30),
    TweenSequenceItem(tween: Tween(begin: 0.97, end: 1.0).chain(CurveTween(curve: AppMotion.spring)), weight: 40),
  ]).animate(_hop);

  @override
  void dispose() {
    _hop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<TodoCubit, TodoState>(
      listenWhen: (a, b) => a.arrival != b.arrival,
      listener: (_, _) => _hop.forward(from: 0),
      child: AnimatedBuilder(
        animation: _hop,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, _lift.value),
          child: Transform.scale(scale: _scale.value, child: child),
        ),
        child: widget.child,
      ),
    );
  }
}

/// A compact one-line secondary action (Ask Echo, Regenerate).
class _QuickAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _QuickAction({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.dividerColor.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: c.primaryGreen),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.nunito(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: c.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Massive Action Card
// ---------------------------------------------------------------------------
class _ActionCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool isPrimary;

  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    required this.isPrimary,
  });

  @override
  State<_ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<_ActionCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.96,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isPrimary
        ? context.colors.textPrimary
        : context.colors.surface;
    final fgColor = widget.isPrimary
        ? context.colors.textInverse
        : context.colors.textPrimary;

    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(24),
            border: widget.isPrimary
                ? null
                : Border.all(
                    color: context.colors.dividerColor.withValues(alpha: 0.5),
                  ),
            boxShadow: [
              BoxShadow(
                color: widget.isPrimary
                    ? context.colors.primaryGreen.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.03),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: GoogleFonts.nunito(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: fgColor,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.subtitle,
                      style: GoogleFonts.nunito(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: fgColor.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Icon(widget.icon, color: fgColor, size: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Summary Card (Signals Captured)
// ---------------------------------------------------------------------------
class _SignalCard extends StatelessWidget {
  final int signalCount;
  const _SignalCard({required this.signalCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: context.colors.dividerColor.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            Icons.inbox_outlined,
            color: context.colors.primaryGreen,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: GoogleFonts.nunito(
                  fontSize: 15,
                  color: context.colors.textSecondary,
                ),
                children: [
                  TextSpan(
                    text: '$signalCount notifications ',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: context.colors.primaryGreen,
                    ),
                  ),
                  const TextSpan(text: 'captured today'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
