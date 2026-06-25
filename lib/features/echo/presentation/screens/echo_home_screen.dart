import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_echo/features/echo/presentation/cubit/briefing_cubit.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/features/echo/presentation/screens/daily_briefing_screen.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/presentation/widgets/timer/next_briefing_timer.dart';
import 'package:project_echo/features/echo/presentation/widgets/generating_view.dart';

class EchoHomeScreen extends StatelessWidget {
  const EchoHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => BriefingCubit(),
      child: const _EchoView(),
    );
  }
}

class _EchoView extends StatefulWidget {
  const _EchoView();

  @override
  State<_EchoView> createState() => _EchoViewState();
}

class _EchoViewState extends State<_EchoView> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<BriefingCubit>().loadCachedBriefing();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: BlocConsumer<BriefingCubit, BriefingState>(
        listener: (context, state) {
          if (state is BriefingReady) {
            Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(
                builder: (_) => DailyBriefingScreen(
                  rawText: state.rawText,
                  ttsText: state.ttsText,
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
  const _InitialView({required this.onGenerate});

  @override
  Widget build(BuildContext context) {
    return _HomeShell(
      actions: [
        _ActionCard(
          title: 'Generate Briefing',
          subtitle: "Synthesize today's intelligence",
          icon: Icons.auto_awesome_rounded,
          onTap: onGenerate,
          isPrimary: true,
        ),
        const SizedBox(height: 20),
        _ActionCard(
          title: 'Ask Echo',
          subtitle: 'Chat with your secure assistant',
          icon: Icons.chat_bubble_outline_rounded,
          onTap: () => context.push('/echo/chat'),
          isPrimary: false,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Cached State — briefing exists for today
// ---------------------------------------------------------------------------
class _CachedView extends StatelessWidget {
  final VoidCallback onPlay;
  final VoidCallback onRegenerate;
  const _CachedView({required this.onPlay, required this.onRegenerate});

  @override
  Widget build(BuildContext context) {
    return _HomeShell(
      actions: [
        _ActionCard(
          title: "Play Today's Briefing",
          subtitle: 'Listen to the cached summary',
          icon: Icons.play_arrow_rounded,
          onTap: onPlay,
          isPrimary: true,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _ActionCard(
                title: 'Ask Echo',
                subtitle: 'Chat',
                icon: Icons.chat_bubble_outline_rounded,
                onTap: () => context.push('/echo/chat'),
                isPrimary: false,
                isSmall: true,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _ActionCard(
                title: 'Regenerate',
                subtitle: 'Update summary',
                icon: Icons.auto_awesome_rounded,
                onTap: onRegenerate,
                isPrimary: false,
                isSmall: true,
              ),
            ),
          ],
        ),
      ],
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
      actions: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 32),
              const SizedBox(height: 12),
              Text(
                'Failed to generate briefing.',
                style: GoogleFonts.nunito(
                  fontWeight: FontWeight.bold,
                  color: context.colors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: GoogleFonts.nunito(
                  fontSize: 12,
                  color: context.colors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _ActionCard(
          title: 'Try Again',
          subtitle: 'Attempt generation again',
          icon: Icons.refresh_rounded,
          onTap: onRetry,
          isPrimary: true,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared shell (header + signal card + action list)
// ---------------------------------------------------------------------------
class _HomeShell extends StatefulWidget {
  final List<Widget> actions;
  const _HomeShell({required this.actions});

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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),

            Text(
              '$greeting,\n$name',
              style: GoogleFonts.oldStandardTt(
                fontSize: 40,
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 24),

            FutureBuilder<List<RawData>>(
              future: IsarDataSource.getAllEntries(),
              builder: (context, snapshot) {
                final count = snapshot.data?.length ?? 0;
                return _SignalCard(signalCount: count);
              },
            ),

            const SizedBox(height: 24),

            const Expanded(child: Center(child: NextBriefingTimer())),

            const SizedBox(height: 24),

            ...widget.actions,

            const SizedBox(height: 48),
          ],
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
  final bool isSmall;

  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    required this.isPrimary,
    this.isSmall = false,
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
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          padding: EdgeInsets.all(widget.isSmall ? 16 : 24),
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
          child: widget.isSmall
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(widget.icon, color: fgColor, size: 24),
                    const SizedBox(height: 24),
                    Text(
                      widget.title,
                      style: GoogleFonts.nunito(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: fgColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.subtitle,
                      style: GoogleFonts.nunito(
                        fontSize: 12,
                        fontWeight: FontWeight.normal,
                        color: fgColor.withValues(alpha: 0.7),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                )
              : Row(
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
