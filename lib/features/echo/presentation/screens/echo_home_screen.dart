import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/home/group_summaries.dart';
import 'package:project_echo/features/echo/data/home/home_feed.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/presentation/widgets/home_sections.dart';
import 'package:project_echo/features/todo/data/todo_generator.dart';
import 'package:project_echo/features/todo/data/todo_store.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_echo/features/echo/presentation/cubit/briefing_cubit.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/services/widget_refresh_service.dart';
import 'package:project_echo/core/services/phone_sync_service.dart';
import 'package:project_echo/core/services/gemini_usage.dart';
import 'package:project_echo/core/services/offline_model_repository.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:project_echo/features/echo/presentation/screens/daily_briefing_screen.dart';
import 'package:project_echo/features/todo/presentation/cubit/todo_cubit.dart';
import 'package:project_echo/features/echo/presentation/widgets/home_glance.dart';
import 'package:project_echo/features/echo/presentation/widgets/home_masthead.dart';
import 'package:project_echo/core/presentation/animations/page_transitions.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/presentation/animations/fade_slide_in.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/widgets/press_feedback.dart';

/// The phone's Home tab. Ask Echo lives in the nav dock (see NavDock).
class EchoHomeScreen extends StatelessWidget {
  const EchoHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // BriefingCubit is provided by MainScaffold (app-scoped) so a briefing
    // keeps generating across tab switches; this screen just renders the view.
    return const _EchoView();
  }
}

class _EchoView extends StatefulWidget {
  const _EchoView();

  @override
  State<_EchoView> createState() => _EchoViewState();
}

class _EchoViewState extends State<_EchoView> with WidgetsBindingObserver {
  /// What Home showed before a briefing started being written. While Echo
  /// writes, Home keeps showing it; his bubble says what he's doing.
  BriefingState? _settled;

  /// What's under the briefing: who's waiting, promises, busy groups. Kept
  /// here, above the briefing's states, so it doesn't reload as they change.
  HomeFeed _feed = HomeFeed.empty;
  StreamSubscription<void>? _isarWatch;
  Timer? _reload;

  /// One line per busy group, by name (see GroupSummaries).
  Map<String, String> _summaries = const {};
  bool _summarising = false;

  Future<void> _loadFeed() async {
    try {
      final now = DateTime.now();
      final feed = await HomeFeed.load(now);
      final kept = await GroupSummaries.cached();
      if (!mounted) return;
      setState(() {
        _feed = feed;
        _summaries = kept;
      });
      unawaited(_summarise(feed, now));
    } catch (_) {
      // Home still shows the briefing and the list.
    }
  }

  /// Sums up the busy groups that have moved on, one call at a time.
  Future<void> _summarise(HomeFeed feed, DateTime now) async {
    if (_summarising || feed.busyGroups.isEmpty) return;
    _summarising = true;
    try {
      final lines = await GroupSummaries.refresh(feed.busyGroups, now);
      if (mounted) setState(() => _summaries = lines);
    } catch (_) {
      // The latest message stands in.
    } finally {
      _summarising = false;
    }
  }

  /// Several notifications often land together; reload once.
  void _reloadSoon() {
    _reload?.cancel();
    _reload = Timer(const Duration(milliseconds: 700), _loadFeed);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadFeed();
    TodoStore.changed.addListener(_reloadSoon);
    IsarDataSource.instance
        .then((isar) {
          if (!mounted) return;
          _isarWatch = isar.rawDatas.watchLazy().listen((_) => _reloadSoon());
        })
        .catchError((_) {});
    // Mirror this phone to a computer on the same Wi-Fi while the app is open.
    PhoneSyncService.instance.startPeriodic();
    PhoneSyncService.instance.syncNow();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    TodoStore.changed.removeListener(_reloadSoon);
    _isarWatch?.cancel();
    _reload?.cancel();
    PhoneSyncService.instance.stopPeriodic();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<BriefingCubit>().loadCachedBriefing();
      _loadFeed();
      WidgetRefreshService.refresh();
      PhoneSyncService.instance.syncNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: context.colors.background,
      body: _FeedScope(
        feed: _feed,
        summaries: _summaries,
        reload: _loadFeed,
        child: BlocConsumer<BriefingCubit, BriefingState>(
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
          builder: (context, bloc) {
            final writing = bloc is BriefingGenerating;
            if (!writing) _settled = bloc;
            final state = writing ? (_settled ?? BriefingInitial()) : bloc;
            // A second tap while writing would only restart it.
            void generate() {
              if (!writing) context.read<BriefingCubit>().generateBriefing();
            }

            if (state is BriefingInitial) {
              return _InitialView(onGenerate: generate);
            }

            if (state is BriefingCached || state is BriefingReady) {
              final rawText = state is BriefingCached
                  ? state.rawText
                  : (state as BriefingReady).rawText;
              return _CachedView(
                onPlay: () =>
                    context.read<BriefingCubit>().playCachedBriefing(rawText),
                onRegenerate: generate,
              );
            }

            if (state is BriefingError) {
              return _ErrorView(
                message: state.message,
                limitReached: state.limitReached,
                onRetry: generate,
              );
            }

            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}

/// Hands Home's feed down to whichever briefing state is showing.
class _FeedScope extends InheritedWidget {
  final HomeFeed feed;
  final Map<String, String> summaries;
  final Future<void> Function() reload;

  const _FeedScope({
    required this.feed,
    required this.summaries,
    required this.reload,
    required super.child,
  });

  static _FeedScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_FeedScope>()!;

  @override
  bool updateShouldNotify(_FeedScope old) =>
      feed != old.feed || summaries != old.summaries;
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
      subtitle: 'No briefing yet today.',
      primary: _ActionCard(
        title: "Make Today's Briefing",
        subtitle: "Everything that's come in, read to you",
        icon: Symbols.play_arrow_rounded,
        onTap: onGenerate,
        isPrimary: true,
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
  const _CachedView({required this.onPlay, required this.onRegenerate});

  @override
  Widget build(BuildContext context) {
    return _HomeShell(
      subtitle: 'Your briefing is ready.',
      primary: _ActionCard(
        title: "Play Today's Briefing",
        subtitle: "Listen to what's come in today",
        icon: Symbols.play_arrow_rounded,
        onTap: onPlay,
        isPrimary: true,
      ),
      secondary: _RegenerateRow(onTap: onRegenerate),
    );
  }
}

// ---------------------------------------------------------------------------
// Error State
// ---------------------------------------------------------------------------
class _ErrorView extends StatelessWidget {
  final String message;
  final bool limitReached;
  final VoidCallback onRetry;
  const _ErrorView({
    required this.message,
    required this.onRetry,
    this.limitReached = false,
  });

  @override
  Widget build(BuildContext context) {
    if (limitReached) {
      return _HomeShell(
        subtitle: "Gemini's limit for today is used up.",
        primary: _LimitCard(message: message),
      );
    }
    return _HomeShell(
      subtitle: "Today's briefing didn't finish.",
      primary: _ActionCard(
        title: 'Try Again',
        subtitle: "Echo couldn't finish the briefing",
        icon: Symbols.refresh_rounded,
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

/// Gemini's daily limit stopped the briefing: say when it's back, and offer
/// the on-device engine when its model is already downloaded.
class _LimitCard extends StatefulWidget {
  final String message;
  const _LimitCard({required this.message});

  @override
  State<_LimitCard> createState() => _LimitCardState();
}

class _LimitCardState extends State<_LimitCard> {
  bool _onDeviceReady = false;

  @override
  void initState() {
    super.initState();
    createOfflineModelRepository().downloadedPathOrNull().then((path) {
      if (mounted && path != null) setState(() => _onDeviceReady = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget button(String label, VoidCallback onTap, {bool filled = true}) =>
        Material(
          color: filled ? c.textPrimary : Colors.transparent,
          shape: StadiumBorder(
            side: filled
                ? BorderSide.none
                : BorderSide(color: c.textPrimary.withValues(alpha: 0.35)),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                label,
                style: GoogleFonts.nunito(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: filled ? c.background : c.textPrimary,
                ),
              ),
            ),
          ),
        );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: c.amberBackground,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Today's briefing couldn't be written",
            style: GoogleFonts.nunito(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.message,
            style: GoogleFonts.nunito(
              fontSize: 14.5,
              height: 1.4,
              color: c.textPrimary.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_onDeviceReady)
                button('Use on-device AI', () async {
                  final briefing = context.read<BriefingCubit>();
                  await context.read<SettingsCubit>().setAiEngine(
                    isOffline: true,
                  );
                  briefing.generateBriefing();
                }),
              button(
                'OK',
                () => context.read<BriefingCubit>().goBack(),
                filled: !_onDeviceReady,
              ),
            ],
          ),
        ],
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

  const _HomeShell({
    required this.subtitle,
    required this.primary,
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

  /// Opens Ask Echo ([start]: a question, or a message to reply to), and
  /// brings Home up to date when it closes.
  Future<void> _ask([Object? start]) async {
    await context.push('/echo/chat', extra: start);
    if (mounted) await _FeedScope.of(context).reload();
  }

  Future<void> _add(RawData entry) async {
    final messenger = ScaffoldMessenger.of(context);
    final dock = MediaQuery.paddingOf(context).bottom;
    final added = await TodoGenerator().addFrom([entry], DateTime.now());
    if (added.isEmpty) return;
    messenger.showSnackBar(
      SnackBar(
        // Above the nav dock, which the tab's bottom padding clears.
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(20, 0, 20, dock),
        content: Text(
          added.length == 1
              ? 'Added “${added.single.title}”'
              : 'Added ${added.length} to your list',
        ),
        // Gone after a few seconds even with a button (Flutter keeps those).
        persist: false,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => TodoStore().remove({for (final i in added) i.id}),
        ),
      ),
    );
  }

  Future<void> _promiseDone(Promise p) async {
    await HomeFeed.markDone(p);
    if (mounted) await _FeedScope.of(context).reload();
  }

  @override
  Widget build(BuildContext context) {
    final greeting = _getGreeting();
    final name = _userName ?? 'Sir';
    final feed = _FeedScope.of(context).feed;

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        // Clears the nav dock (MainScaffold sets the bottom padding).
        padding: EdgeInsets.fromLTRB(
          0,
          12,
          0,
          MediaQuery.paddingOf(context).bottom + 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),

            // ── Sections to swipe through (full width, so they don't clip
            // at the page margins mid-swipe) ────────────────────────────────
            FadeSlideIn(
              child: HomeGlance(
                masthead: HomeMasthead(
                  greeting: greeting,
                  name: name,
                  fallback: widget.subtitle,
                  waiting: feed.needsYou.length,
                ),
              ),
            ),

            const SizedBox(height: 20),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Primary action ──────────────────────────────────────
                  FadeSlideIn(
                    delay: AppMotion.staggerDelay(2),
                    child: widget.primary,
                  ),

                  // ── Secondary action, right under the primary one ───────
                  if (widget.secondary != null) ...[
                    const SizedBox(height: 12),
                    FadeSlideIn(
                      delay: AppMotion.staggerDelay(3),
                      child: widget.secondary!,
                    ),
                  ],

                  FadeSlideIn(
                    delay: AppMotion.staggerDelay(4),
                    child: NeedsYouSection(
                      entries: feed.needsYou,
                      onReply: _ask,
                      onAdd: _add,
                      onOpenAsk: _ask,
                    ),
                  ),
                  FadeSlideIn(
                    delay: AppMotion.staggerDelay(5),
                    child: UpNextSection(onSeeAll: () => context.go('/todo')),
                  ),
                  FadeSlideIn(
                    delay: AppMotion.staggerDelay(6),
                    child: PromisesSection(
                      promises: feed.promises,
                      onAdd: (p) => _add(p.entry),
                      onDone: _promiseDone,
                    ),
                  ),
                  FadeSlideIn(
                    delay: AppMotion.staggerDelay(7),
                    child: BusyGroupsSection(
                      groups: feed.busyGroups,
                      summaries: _FeedScope.of(context).summaries,
                      onCatchUp: (group) => _ask('Catch me up on $group'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RegenerateRow extends StatefulWidget {
  final VoidCallback onTap;
  const _RegenerateRow({required this.onTap});

  @override
  State<_RegenerateRow> createState() => _RegenerateRowState();
}

class _RegenerateRowState extends State<_RegenerateRow> {
  DateTime? _madeAt;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      final raw = prefs.getString('cached_briefing_time');
      final at = raw == null ? null : DateTime.tryParse(raw);
      final now = DateTime.now();
      final today =
          at != null &&
          at.year == now.year &&
          at.month == now.month &&
          at.day == now.day;
      if (mounted && today) setState(() => _madeAt = at);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final at = _madeAt;
    return PressFeedback(
      scale: 0.98,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: c.dividerColor.withValues(alpha: 0.6)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            child: Row(
              children: [
                Icon(Symbols.refresh_rounded, size: 20, color: c.textSecondary),
                const SizedBox(width: 12),
                Text(
                  'Regenerate',
                  style: GoogleFonts.nunito(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ),
                const Spacer(),
                // Running low on Gemini: the count replaces the time it was made.
                ValueListenableBuilder<GeminiUsageSnapshot?>(
                  valueListenable: GeminiUsage.instance.snapshot,
                  builder: (context, usage, _) {
                    final cloud = !context.select(
                      (SettingsCubit s) => s.state.isOfflineEngine,
                    );
                    final left = usage?.left;
                    if (cloud && usage != null && left != null && usage.isLow) {
                      return Text(
                        left == 0
                            ? 'Gemini back at ${clockTime(usage.resetsAt)}'
                            : '$left Gemini ${left == 1 ? 'request' : 'requests'} left',
                        style: GoogleFonts.nunito(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: context.warmAccent,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      );
                    }
                    return Text(
                      at == null ? 'Update summary' : 'Made at ${_clock(at)}',
                      style: GoogleFonts.nunito(
                        fontSize: 12.5,
                        color: c.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _clock(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
  }
}

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
              Icon(widget.icon, fill: 1, color: fgColor, size: 32),
            ],
          ),
        ),
      ),
    );
  }
}
