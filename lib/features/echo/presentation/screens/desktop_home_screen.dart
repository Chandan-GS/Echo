import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/core/services/echo_tts.dart';
import 'package:project_echo/core/services/streak_service.dart';
import 'package:project_echo/core/services/widget_refresh_service.dart';
import 'package:project_echo/core/services/echo_server_service.dart';
import 'package:project_echo/core/presentation/animations/fade_slide_in.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_echo/features/echo/presentation/cubit/briefing_cubit.dart';
import 'package:project_echo/features/echo/presentation/screens/ask_ai_screen.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_mascot.dart';
import 'package:project_echo/features/echo/presentation/widgets/streak_flame.dart';
import 'package:project_echo/features/echo/presentation/widgets/siri_waveform_visualizer.dart';
import 'package:project_echo/features/echo/presentation/widgets/rich_transcript.dart';
import 'package:project_echo/features/echo/presentation/widgets/generating_view.dart';
import 'package:project_echo/core/utils/time_utils.dart';
import 'dart:async';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_state.dart';

/// The desktop Today screen — a genuine three-pane workspace rather than a
/// centered phone column. The sidebar is supplied by [DesktopShell]; this
/// builds the center briefing surface (with inline playback, so nothing is
/// pushed as a full-screen route the way phone does) and a right rail with
/// Echo's presence, the next-briefing countdown, the streak, and a compact
/// engine card.
class DesktopHomeScreen extends StatefulWidget {
  /// Whether the inline Ask Echo chat is showing in the center pane (in place
  /// of the briefing surface). Owned by the shell so the sidebar's "Ask Echo"
  /// item and the home ask bar drive the same state.
  final bool chatActive;

  /// Opens the inline chat (from the bottom ask bar).
  final VoidCallback onOpenChat;

  /// Returns from the inline chat to the briefing.
  final VoidCallback onCloseChat;

  /// Switches the shell to the Settings/Profile tab (from the engine card).
  final VoidCallback onOpenSettings;

  const DesktopHomeScreen({
    super.key,
    required this.chatActive,
    required this.onOpenChat,
    required this.onCloseChat,
    required this.onOpenSettings,
  });

  @override
  State<DesktopHomeScreen> createState() => _DesktopHomeScreenState();
}

class _DesktopHomeScreenState extends State<DesktopHomeScreen>
    with WidgetsBindingObserver {
  String? _userName;
  int _captured = 0;
  StreakInfo _streak = StreakInfo.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Reflect fresh snapshots the phone pushes to this computer's engine.
    EchoServerService.instance.syncTick.addListener(_onSynced);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    EchoServerService.instance.syncTick.removeListener(_onSynced);
    super.dispose();
  }

  void _onSynced() {
    if (!mounted) return;
    _load();
    // The synced briefing/notifications just landed in local storage — pull
    // the cached briefing into the cubit so Today updates without a reload.
    context.read<BriefingCubit>().loadCachedBriefing();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<BriefingCubit>().loadCachedBriefing();
      WidgetRefreshService.refresh();
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entries = await IsarDataSource.getAllEntries();
      final streak = await StreakService().current();
      if (!mounted) return;
      setState(() {
        _userName = prefs.getString('user_name');
        _captured = entries.length;
        _streak = streak;
      });
    } catch (_) {}
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h >= 5 && h < 12) return 'Good morning';
    if (h >= 12 && h < 17) return 'Good afternoon';
    if (h >= 17 && h < 22) return 'Good evening';
    return 'Good night';
  }

  String _today() {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June', 'July',
      'August', 'September', 'October', 'November', 'December'
    ];
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
    ];
    final n = DateTime.now();
    return '${weekdays[n.weekday - 1]}, ${n.day} ${months[n.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final name = (_userName?.trim().isNotEmpty ?? false) ? _userName!.trim() : null;

    // Calm cross-fade between the full briefing workspace (with rail) and the
    // focused chat. Each branch is a complete, independently-valid layout, so
    // the dissolve never produces a half-built frame that overflows. A gentle
    // easeInOut fade — no scale or slide — keeps it unhurried.
    return SafeArea(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 360),
        switchInCurve: Curves.easeInOut,
        switchOutCurve: Curves.easeInOut,
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        child: SizedBox.expand(
          // Key by mode so the switcher animates on the briefing↔chat flip;
          // SizedBox.expand gives each branch tight full-size constraints.
          key: ValueKey(widget.chatActive),
          child: widget.chatActive
              ? _chatLayout(context)
              : _briefingLayout(context, name),
        ),
      ),
    );
  }

  Widget _briefingLayout(BuildContext context, String? name) {
    final colors = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Show the rail only when there's real room for a three-pane split;
        // below this it would overflow, so drop it and let the center breathe.
        final showRail = constraints.maxWidth >= 720;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _briefingCenter(context, name)),
            if (showRail) _rightRail(context, colors),
          ],
        );
      },
    );
  }

  Widget _briefingCenter(BuildContext context, String? name) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 32, 32, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FadeSlideIn(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name != null ? '${_greeting()},\n$name' : _greeting(),
                        style: GoogleFonts.oldStandardTt(
                          fontSize: 40,
                          fontWeight: FontWeight.w700,
                          height: 1.08,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _today(),
                        style: GoogleFonts.nunito(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                _CapturedPill(count: _captured),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: FadeSlideIn(
              delay: AppMotion.staggerDelay(1),
              child: BlocBuilder<BriefingCubit, BriefingState>(
                builder: (context, state) => _briefingSurface(context, state),
              ),
            ),
          ),
          const SizedBox(height: 20),
          FadeSlideIn(
            delay: AppMotion.staggerDelay(2),
            child: _AskEchoBar(onTap: widget.onOpenChat),
          ),
        ],
      ),
    );
  }

  Widget _chatLayout(BuildContext context) {
    // Full-width focused chat — no rail, no greeting.
    return _ChatPane(onClose: widget.onCloseChat);
  }

  Widget _rightRail(BuildContext context, AppColors colors) {
    return Container(
      width: 320,
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: colors.dividerColor)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _NextBriefingRailCard(),
            const SizedBox(height: 16),
            _StreakCard(streak: _streak),
            const SizedBox(height: 16),
            _EngineRailCard(onManage: widget.onOpenSettings),
          ],
        ),
      ),
    );
  }

  Widget _briefingSurface(BuildContext context, BriefingState state) {
    if (state is BriefingGenerating) {
      return _SurfaceCard(child: GeneratingView(partial: state.partial));
    }
    if (state is BriefingCached || state is BriefingReady) {
      final raw = state is BriefingCached
          ? state.rawText
          : (state as BriefingReady).rawText;
      final tts = state is BriefingCached
          ? state.ttsText
          : (state as BriefingReady).ttsText;
      return _InlineBriefingPlayer(
        key: ValueKey(raw.hashCode),
        rawText: raw,
        ttsText: tts,
        onRegenerate: () => context.read<BriefingCubit>().generateBriefing(),
        onHeard: _load,
      );
    }
    if (state is BriefingError) {
      return _SurfaceCard(
        child: _CenteredMessage(
          icon: Icons.error_outline_rounded,
          title: "We couldn't generate your briefing.",
          subtitle: state.message,
          actionLabel: 'Try again',
          onAction: () => context.read<BriefingCubit>().generateBriefing(),
        ),
      );
    }
    // Initial
    return _SurfaceCard(
      child: _CenteredMessage(
        icon: Icons.auto_awesome_rounded,
        title: 'No briefing yet',
        subtitle: "Generate today's briefing to get started.",
        actionLabel: 'Generate briefing',
        onAction: () => context.read<BriefingCubit>().generateBriefing(),
      ),
    );
  }
}

// ── Center building blocks ────────────────────────────────────────────────

/// The raised surface the briefing content sits on.
class _SurfaceCard extends StatelessWidget {
  final Widget child;
  const _SurfaceCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: colors.dividerColor.withValues(alpha: 0.6)),
      ),
      child: child,
    );
  }
}

/// The inline audio player + transcript — desktop's replacement for pushing
/// DailyBriefingScreen. Owns its own TTS and records the streak on first play.
class _InlineBriefingPlayer extends StatefulWidget {
  final String rawText;
  final String ttsText;
  final VoidCallback onRegenerate;
  final VoidCallback onHeard;

  const _InlineBriefingPlayer({
    super.key,
    required this.rawText,
    required this.ttsText,
    required this.onRegenerate,
    required this.onHeard,
  });

  @override
  State<_InlineBriefingPlayer> createState() => _InlineBriefingPlayerState();
}

class _InlineBriefingPlayerState extends State<_InlineBriefingPlayer> {
  final FlutterTts _tts = FlutterTts();
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    await EchoTts.applyVoicePreferences(_tts);
    await _tts.setVolume(1.0);
    _tts.setStartHandler(() {
      if (mounted) setState(() => _isPlaying = true);
      _recordHeard();
    });
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _isPlaying = false);
    });
    _tts.setCancelHandler(() {
      if (mounted) setState(() => _isPlaying = false);
    });
  }

  Future<void> _recordHeard() async {
    await StreakService().recordHeard();
    WidgetRefreshService.refresh();
    widget.onHeard();
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _toggle() async {
    HapticFeedback.lightImpact();
    if (_isPlaying) {
      await _tts.stop();
    } else {
      await _tts.speak(widget.ttsText);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Player: waveform + play/stop
          Row(
            children: [
              _PlayCircle(isPlaying: _isPlaying, onTap: _toggle),
              const SizedBox(width: 20),
              Expanded(
                child: SizedBox(
                  height: 64,
                  child: SiriWaveformVisualizer(
                    isPlaying: _isPlaying,
                    onTap: _toggle,
                    amplitude: 2.5,
                    height: 64,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Divider(color: colors.dividerColor.withValues(alpha: 0.6), height: 1),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Transcript',
                style: GoogleFonts.oldStandardTt(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              _RegenerateButton(onTap: widget.onRegenerate),
            ],
          ),
          const SizedBox(height: 14),
          // Transcript scrolls within the card, fading at the bottom edge.
          Expanded(
            child: ShaderMask(
              shaderCallback: (rect) => LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.white, Colors.white, Colors.transparent],
                stops: const [0.0, 0.9, 1.0],
              ).createShader(rect),
              blendMode: BlendMode.dstIn,
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: RichTranscript(rawText: widget.rawText),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayCircle extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onTap;
  const _PlayCircle({required this.isPlaying, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.primaryGreen,
          boxShadow: [
            BoxShadow(
              color: colors.primaryGreen.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Icon(
          isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
          color: Colors.white,
          size: 30,
        ),
      ),
    );
  }
}

class _RegenerateButton extends StatelessWidget {
  final VoidCallback onTap;
  const _RegenerateButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.background,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.refresh_rounded, size: 16, color: colors.textSecondary),
              const SizedBox(width: 7),
              Text(
                'Regenerate',
                style: GoogleFonts.nunito(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        // Centre when there's room, scroll when the card is short — never
        // overflow at small window heights.
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const EchoMascot(state: EchoState.idle, size: 120),
                const SizedBox(height: 20),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.oldStandardTt(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.nunito(
                      fontSize: 14, color: colors.textSecondary),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: onAction,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.textPrimary,
                    foregroundColor: colors.textInverse,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 26, vertical: 15),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: Text(
                    actionLabel,
                    style: GoogleFonts.nunito(
                        fontSize: 15, fontWeight: FontWeight.w800),
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

/// The inline Ask Echo conversation, shown in the center pane in place of the
/// briefing surface. Reuses the embedded [AskAiScreen] (its own input + cubit)
/// under a slim header with a way back to the briefing.
class _ChatPane extends StatelessWidget {
  final VoidCallback onClose;
  const _ChatPane({required this.onClose});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // No card, no border, no separate surface color — this sits directly on
    // the shell's own background (same as the briefing pane), so it reads as
    // one continuous screen instead of a box floating inside the window.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(40, 28, 40, 4),
          child: Row(
            children: [
              Icon(Icons.chat_bubble_rounded, size: 17, color: colors.primaryGreen),
              const SizedBox(width: 7),
              Text(
                'Ask Echo',
                style: GoogleFonts.oldStandardTt(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const Spacer(),
              Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onClose,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_back_rounded,
                            size: 15, color: colors.textSecondary),
                        const SizedBox(width: 6),
                        Text(
                          'Back to briefing',
                          style: GoogleFonts.nunito(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // The embedded chat renders its own message list + input bar, full
        // bleed on the shell's background — same treatment as the phone app.
        const Expanded(child: AskAiScreen(embedded: true)),
      ],
    );
  }
}

class _CapturedPill extends StatelessWidget {
  final int count;
  const _CapturedPill({required this.count});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.dividerColor.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_rounded, size: 18, color: colors.primaryGreen),
          const SizedBox(width: 10),
          RichText(
            text: TextSpan(
              style: GoogleFonts.nunito(fontSize: 13, height: 1.3),
              children: [
                TextSpan(
                  text: '$count\n',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: colors.primaryGreen,
                  ),
                ),
                TextSpan(
                  text: 'captured today',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The bottom "Ask Echo" bar — a faux input that opens the Ask Echo tab.
class _AskEchoBar extends StatelessWidget {
  final VoidCallback onTap;
  const _AskEchoBar({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(30),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: colors.dividerColor.withValues(alpha: 0.6)),
          ),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 18, color: colors.primaryGreen),
              const SizedBox(width: 12),
              Text(
                'Ask Echo',
                style: GoogleFonts.nunito(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Right rail building blocks ────────────────────────────────────────────

/// A neutral card wrapper for rail widgets.
class _RailCard extends StatelessWidget {
  final Widget child;
  const _RailCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.dividerColor.withValues(alpha: 0.6)),
      ),
      child: child,
    );
  }
}

/// Clean text-based next-briefing countdown for the rail — the circular dial
/// widget reads as cramped at this width, so this matches the desktop mockup:
/// a label, a big tabular countdown, and the scheduled time.
class _NextBriefingRailCard extends StatefulWidget {
  const _NextBriefingRailCard();

  @override
  State<_NextBriefingRailCard> createState() => _NextBriefingRailCardState();
}

class _NextBriefingRailCardState extends State<_NextBriefingRailCard> {
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  DateTime _nextBriefing(List<String> times) {
    final instances = <DateTime>[];
    for (final d in [_now, _now.add(const Duration(days: 1))]) {
      for (final t in times) {
        final p = parseBriefingTime(t);
        if (p == null) continue;
        instances.add(DateTime(d.year, d.month, d.day, p.hour, p.minute));
      }
    }
    if (instances.isEmpty) {
      return _now.hour < 7
          ? DateTime(_now.year, _now.month, _now.day, 7)
          : DateTime(_now.year, _now.month, _now.day + 1, 7);
    }
    instances.sort();
    return instances.firstWhere((dt) => dt.isAfter(_now),
        orElse: () => _now.add(const Duration(hours: 24)));
  }

  String _fmtRemaining(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _fmtTime(DateTime dt) {
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final h12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    return '${h12.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $period';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        final times =
            state.briefingTimes.isEmpty ? const ['07:00'] : state.briefingTimes;
        final next = _nextBriefing(times);
        final remaining = next.difference(_now);
        return _RailCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'NEXT BRIEFING',
                style: GoogleFonts.nunito(
                  fontSize: 11,
                  letterSpacing: 1.8,
                  fontWeight: FontWeight.w800,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  _fmtRemaining(remaining),
                  style: GoogleFonts.nunito(
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                    color: colors.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'at ${_fmtTime(next)}',
                style: GoogleFonts.nunito(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: colors.primaryGreen,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StreakCard extends StatelessWidget {
  final StreakInfo streak;
  const _StreakCard({required this.streak});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return _RailCard(
      child: Row(
        children: [
          const StreakFlame(size: 26, glow: false),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${streak.current}',
                  style: GoogleFonts.nunito(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'day streak · longest ${streak.longest}',
                  style: GoogleFonts.nunito(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact engine status for the rail, with a shortcut to the full controls in
/// Settings (which owns the model download / run-here toggle).
class _EngineRailCard extends StatelessWidget {
  final VoidCallback onManage;
  const _EngineRailCard({required this.onManage});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        final running = state.runDesktopEngineHere;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: running
                ? colors.lightGreenBackground.withValues(alpha: 0.35)
                : colors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: running
                  ? colors.primaryGreen.withValues(alpha: 0.35)
                  : colors.dividerColor.withValues(alpha: 0.6),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      'Echo Engine',
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.nunito(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colors.background,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'OPTIONAL',
                      style: GoogleFonts.nunito(
                        fontSize: 9.5,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w800,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: running ? colors.primaryGreen : colors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    running ? 'Running on this computer' : 'Off',
                    style: GoogleFonts.nunito(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Use this computer as Echo\'s brain to run a larger local model. '
                'Your phone stays the default.',
                style: GoogleFonts.nunito(fontSize: 12.5, color: colors.textSecondary),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: onManage,
                child: Text(
                  running ? 'Manage in Settings →' : 'Set up in Settings →',
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: colors.primaryGreen,
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
