import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/animations/page_transitions.dart';
import 'package:project_echo/core/presentation/widgets/echo_app_bar.dart';
import 'package:project_echo/core/services/analytics_service.dart';
import 'package:project_echo/core/services/engine_gate.dart';
import 'package:project_echo/core/services/streak_service.dart';
import 'package:project_echo/core/services/voice/echo_voice.dart';
import 'package:project_echo/core/services/widget_refresh_service.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/data/datasources/briefing_prompt.dart';
import 'package:project_echo/features/echo/data/wrap/evening_wrap.dart';
import 'package:project_echo/features/echo/data/wrap/wrap_store.dart';
import 'package:project_echo/features/echo/presentation/cubit/briefing_cubit.dart';
import 'package:project_echo/features/echo/presentation/screens/streak_celebration_screen.dart';
import 'package:project_echo/features/echo/presentation/widgets/briefing_controls.dart';
import 'package:project_echo/features/echo/presentation/widgets/siri_waveform_visualizer.dart';
import 'package:project_echo/features/todo/presentation/cubit/todo_cubit.dart';
import 'package:project_echo/features/todo/presentation/widgets/briefing_list_prompt.dart';
import 'package:project_echo/features/todo/presentation/widgets/drafting_skeleton.dart';

class DailyBriefingScreen extends StatefulWidget {
  /// 'morning' or 'evening': which of the two opens first.
  final String mode;

  /// The morning briefing's text when the caller already has it; otherwise
  /// the screen reads today's from the briefing store.
  final String? rawText;
  final String? ttsText;
  final VoidCallback? onReset;

  /// When true, playback starts immediately once TTS is ready — used when the
  /// screen was reached via a notification/widget tap-to-play, so the user
  /// doesn't have to tap the waveform themselves. Never applies to the wrap.
  final bool autoPlay;

  /// The home screen's to-do list, when this route can see it. The transcript
  /// ends with an offer to make (or update) it.
  final TodoCubit? todoCubit;

  const DailyBriefingScreen({
    super.key,
    this.mode = 'morning',
    this.rawText,
    this.ttsText,
    this.onReset,
    this.autoPlay = false,
    this.todoCubit,
  });

  @override
  State<DailyBriefingScreen> createState() => _DailyBriefingScreenState();
}

class _DailyBriefingScreenState extends State<DailyBriefingScreen>
    with WidgetsBindingObserver {
  final _voice = EchoVoice.instance;
  var _isPlaying = false;
  bool _rewriting = false;
  late var _evening = widget.mode == 'evening';

  EveningWrap? _wrap;

  /// Whether an engine can write the morning briefing; null until known.
  bool? _canWrite;

  late final BriefingCubit _briefing;
  late final bool _ownsBriefing;
  late final TodoCubit _todo;
  late final bool _ownsTodo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final briefing = _tryRead<BriefingCubit>();
    _ownsBriefing = briefing == null;
    _briefing = briefing ?? BriefingCubit();
    final todo = widget.todoCubit ?? _tryRead<TodoCubit>();
    _ownsTodo = todo == null;
    _todo = todo ?? TodoCubit();
    _loadWrap();
    EngineGate.current().then((engine) {
      if (mounted) setState(() => _canWrite = engine != null);
    });
    if (widget.autoPlay && !_evening) {
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) _play();
      });
    }
  }

  /// Comes from the shell's providers when this route can see them.
  T? _tryRead<T extends StateStreamableSource<Object?>>() {
    try {
      return context.read<T>();
    } catch (_) {
      return null;
    }
  }

  /// The wrap is built fresh each time: a to-do ticked or a reply sent
  /// changes it, and the date may have rolled over.
  Future<void> _loadWrap() async {
    final wrap = await WrapStore.build(DateTime.now());
    if (mounted) setState(() => _wrap = wrap);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _evening && !_isPlaying) {
      _loadWrap();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _voice.stop();
    if (_ownsBriefing) _briefing.close();
    if (_ownsTodo) _todo.close();
    super.dispose();
  }

  String? get _morningText {
    if (widget.rawText != null) return widget.rawText;
    final s = _briefing.state;
    return switch (s) {
      BriefingCached() => s.rawText,
      BriefingReady() => s.rawText,
      _ => null,
    };
  }

  String? get _currentText => _evening ? _wrap?.rawText : _morningText;

  String get _ttsText => !_evening && widget.ttsText != null
      ? widget.ttsText!
      : stripForTts(_currentText ?? '');

  /// Echo reads it in his voice: the natural one when it's downloaded, the
  /// phone's otherwise. Only ever after a tap, or the briefing's own
  /// tap-to-play notification.
  Future<void> _play() async {
    final text = _ttsText;
    if (text.isEmpty) return;
    await _voice.stop();
    if (!mounted) return;
    setState(() => _isPlaying = true);
    _celebrateStreakIfAdvanced();
    _voice.sayAll(text.replaceAll('**', ''));
    await _voice.finished;
    if (mounted) setState(() => _isPlaying = false);
  }

  /// Records that a briefing was heard and, if the streak actually advanced
  /// (i.e. this is the first play today — recordHeard() is a no-op on
  /// subsequent toggles the same day), shows the full-screen celebration.
  Future<void> _celebrateStreakIfAdvanced() async {
    Analytics.track(_evening ? 'evening_wrap_played' : 'briefing_played');
    final service = StreakService();
    final before = await service.current();
    final after = _evening
        ? await service.recordEveningWrapCleared()
        : await service.recordHeard();
    // Push the fresh streak/heard-days to the home-screen widgets.
    WidgetRefreshService.refresh();
    if (mounted && after.current != before.current) {
      Navigator.of(
        context,
        rootNavigator: true,
      ).push(bouncyRoute(StreakCelebrationScreen(days: after.current)));
    }
  }

  Future<void> _togglePlayback() async {
    HapticFeedback.lightImpact();
    if (_isPlaying) {
      await _voice.stop();
    } else {
      await _play();
    }
  }

  /// Writes a fresh briefing on the shared cubit and heads back to Today,
  /// whose card shows the progress.
  void _writeAgain() {
    _voice.stop();
    _rewriting = true;
    context.read<BriefingCubit>().generateBriefing();
    Navigator.of(context).maybePop();
  }

  void _setEvening(bool evening) {
    if (evening == _evening) return;
    _voice.stop();
    setState(() {
      _evening = evening;
      _isPlaying = false;
      if (evening) _wrap = null;
    });
    if (evening) _loadWrap();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_rewriting) widget.onReset?.call();
      },
      child: Scaffold(
        backgroundColor: c.background,
        appBar: EchoAppBar(
          title: _evening ? 'Evening wrap' : 'Morning briefing',
          onBackPressed: () => Navigator.of(context).maybePop(),
          actions: [
            if (_currentText?.isNotEmpty ?? false)
              IconButton(
                tooltip: 'Write it again',
                onPressed: _writeAgain,
                icon: Icon(
                  Symbols.refresh_rounded,
                  size: 24,
                  color: c.textPrimary,
                ),
              ),
          ],
        ),
        body: BlocProvider.value(
          value: _todo,
          child: BlocBuilder<BriefingCubit, BriefingState>(
            bloc: _briefing,
            builder: (context, briefingState) {
              final text = _currentText;
              final hasText = text != null && text.isNotEmpty;
              return Column(
                children: [
                  const SizedBox(height: 6),
                  BriefingKindSwitch(evening: _evening, onChanged: _setEvening),
                  // Waveform — tap it to play/pause. Flexible so it shrinks
                  // to fit short layouts instead of overflowing.
                  Expanded(
                    flex: 3,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: SiriWaveformVisualizer(
                              isPlaying: _isPlaying,
                              onTap: hasText ? _togglePlayback : () {},
                              amplitude: 3,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        AnimatedOpacity(
                          opacity: _isPlaying || !hasText ? 0.0 : 1.0,
                          duration: const Duration(milliseconds: 400),
                          child: Text(
                            'Tap to play',
                            style: GoogleFonts.nunito(
                              fontSize: 12,
                              color: c.textSecondary,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 6,
                    child: _TranscriptPanel(
                      child: _evening
                          ? _eveningBody()
                          : _morningBody(briefingState),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _morningBody(BriefingState state) {
    final c = context.colors;
    final text = _morningText;
    if (text != null && text.isNotEmpty) {
      return _Transcript(rawText: text, showList: true);
    }
    if (state is BriefingGenerating) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state.partial.isEmpty ? 'Writing your briefing…' : state.partial,
            style: GoogleFonts.nunito(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: c.primaryGreen,
            ),
          ),
          const SizedBox(height: 14),
          const DraftingSkeleton(rows: 4, writing: true),
        ],
      );
    }
    if (state is BriefingError) {
      return _Empty(
        message: state.message,
        action: 'Try again',
        onAction: () => _briefing.generateBriefing(),
      );
    }
    final canWrite = _canWrite;
    if (canWrite == null) return const SizedBox.shrink();
    if (!canWrite) {
      return _Empty(
        message:
            'Your morning briefing needs a way to write. Choose one in '
            'Settings, or switch to Evening for a wrap that works without it.',
        action: 'Open Settings',
        onAction: () => context.push('/settings'),
      );
    }
    return _Empty(
      message: 'No briefing yet today.',
      action: "Make today's briefing",
      onAction: () => _briefing.generateBriefing(),
    );
  }

  Widget _eveningBody() {
    final wrap = _wrap;
    if (wrap == null) return const SizedBox.shrink();
    return _Transcript(rawText: wrap.rawText, showList: !wrap.noData);
  }
}

/// The rounded sheet the transcript sits on, fading out at the bottom.
class _TranscriptPanel extends StatelessWidget {
  final Widget child;
  const _TranscriptPanel({required this.child});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [c.surface, c.background],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Transcript',
              style: GoogleFonts.oldStandardTt(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: child),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 60,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              c.background.withValues(alpha: 0),
                              c.background,
                            ],
                          ),
                        ),
                      ),
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

class _Transcript extends StatelessWidget {
  final String rawText;
  final bool showList;
  const _Transcript({required this.rawText, required this.showList});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    physics: const BouncingScrollPhysics(),
    child: Padding(
      // The list offer ends the transcript; leave room so it scrolls clear of
      // the fade below.
      padding: EdgeInsets.only(bottom: showList ? 120 : 60),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ValueListenableBuilder<String?>(
            valueListenable: EchoVoice.instance.speaking,
            builder: (context, spoken, _) =>
                SpokenTranscript(rawText: rawText, spoken: spoken),
          ),
          if (showList) const BriefingListPrompt(),
        ],
      ),
    ),
  );
}

/// What to say when there's no transcript, and the one thing to do next.
class _Empty extends StatelessWidget {
  final String message;
  final String action;
  final VoidCallback onAction;
  const _Empty({
    required this.message,
    required this.action,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 80),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: GoogleFonts.nunito(
                fontSize: 16,
                height: 1.6,
                color: c.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: c.primaryGreen,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                action,
                style: GoogleFonts.nunito(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
