import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:project_echo/core/services/echo_tts.dart';
import 'package:project_echo/core/presentation/animations/page_transitions.dart';
import 'package:project_echo/core/services/streak_service.dart';
import 'package:project_echo/core/services/widget_refresh_service.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/presentation/widgets/echo_app_bar.dart';
import 'package:project_echo/features/echo/presentation/widgets/siri_waveform_visualizer.dart';
import 'package:project_echo/features/echo/presentation/widgets/rich_transcript.dart';
import 'package:project_echo/features/echo/presentation/screens/streak_celebration_screen.dart';

class DailyBriefingScreen extends StatefulWidget {
  final String rawText;
  final String ttsText;
  final VoidCallback onReset;

  /// When true, playback starts immediately once TTS is ready — used when the
  /// screen was reached via a notification/widget tap-to-play, so the user
  /// doesn't have to tap the waveform themselves.
  final bool autoPlay;

  const DailyBriefingScreen({
    super.key,
    required this.rawText,
    required this.ttsText,
    required this.onReset,
    this.autoPlay = false,
  });

  @override
  State<DailyBriefingScreen> createState() => _DailyBriefingScreenState();
}

class _DailyBriefingScreenState extends State<DailyBriefingScreen> {
  final FlutterTts _tts = FlutterTts();
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) _setupTts();
    });
  }

  Future<void> _setupTts() async {
    // Apply the voice + rate the user chose during onboarding (or in settings).
    await EchoTts.applyVoicePreferences(_tts);
    await _tts.setVolume(1.0);

    _tts.setStartHandler(() {
      if (mounted) setState(() => _isPlaying = true);
      _celebrateStreakIfAdvanced();
    });
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _isPlaying = false);
    });
    _tts.setCancelHandler(() {
      if (mounted) setState(() => _isPlaying = false);
    });

    if (widget.autoPlay) {
      await _tts.speak(widget.ttsText);
    }
  }

  /// Records that a briefing was heard and, if the streak actually advanced
  /// (i.e. this is the first play today — recordHeard() is a no-op on
  /// subsequent toggles the same day), shows the full-screen celebration.
  Future<void> _celebrateStreakIfAdvanced() async {
    final service = StreakService();
    final before = await service.current();
    final after = await service.recordHeard();
    // Push the fresh streak/heard-days to the home-screen widgets.
    WidgetRefreshService.refresh();
    if (mounted && after.current != before.current) {
      Navigator.of(context, rootNavigator: true).push(
        bouncyRoute(StreakCelebrationScreen(days: after.current)),
      );
    }
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  void _togglePlayback() async {
    HapticFeedback.lightImpact();
    if (_isPlaying) {
      await _tts.stop();
    } else {
      await _tts.speak(widget.ttsText);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          widget.onReset();
        }
      },
      child: Scaffold(
        backgroundColor: context.colors.background,
        appBar: EchoAppBar(
          title: 'Morning Briefing',
          onBackPressed: () => Navigator.of(context, rootNavigator: true).pop(),
        ),
        body: Column(
          children: [
            // ── Top half: Waveform (tap to play/pause) ──────────────────────
            Expanded(
              flex: 3,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Waveform — tap it to play/pause. Flexible so it shrinks to
                  // fit short/landscape layouts instead of overflowing.
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: SiriWaveformVisualizer(
                        isPlaying: _isPlaying,
                        onTap: _togglePlayback,
                        amplitude: 3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Subtle hint text
                  AnimatedOpacity(
                    opacity: _isPlaying ? 0.0 : 1.0,
                    duration: const Duration(milliseconds: 400),
                    child: Text(
                      'Tap to play',
                      style: GoogleFonts.nunito(
                        fontSize: 12,
                        color: context.colors.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Bottom half: Rich Transcript ─────────────────────────────────
            Expanded(
              flex: 6,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [context.colors.surface, context.colors.background],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(36),
                  ),
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Transcript',
                            style: GoogleFonts.oldStandardTt(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: context.colors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Expanded(
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: SingleChildScrollView(
                                physics: const BouncingScrollPhysics(),
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 60),
                                  child: RichTranscript(
                                    rawText: widget.rawText,
                                  ),
                                ),
                              ),
                            ),
                            // Fade gradient overlay at the bottom
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              height: 60,
                              child: IgnorePointer(
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        context.colors.background.withValues(
                                          alpha: 0.0,
                                        ),
                                        context.colors.background,
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}
