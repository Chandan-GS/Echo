import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/presentation/widgets/echo_app_bar.dart';
import 'package:project_echo/features/echo/presentation/widgets/siri_waveform_visualizer.dart';
import 'package:project_echo/features/echo/presentation/widgets/rich_transcript.dart';

class DailyBriefingScreen extends StatefulWidget {
  final String rawText;
  final String ttsText;
  final VoidCallback onReset;

  const DailyBriefingScreen({
    super.key,
    required this.rawText,
    required this.ttsText,
    required this.onReset,
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
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.48);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);

    try {
      final voices = await _tts.getVoices;
      for (var voice in voices) {
        final name = voice['name'].toString().toLowerCase();
        final locale = voice['locale'].toString().toLowerCase();
        if ((locale.contains('en-gb')) &&
            (name.contains('male') ||
                name.contains('daniel') ||
                name.contains('network'))) {
          await _tts.setVoice({
            "name": voice["name"],
            "locale": voice["locale"],
          });
          break;
        }
      }
    } catch (_) {}

    _tts.setStartHandler(() {
      if (mounted) setState(() => _isPlaying = true);
    });
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _isPlaying = false);
    });
    _tts.setCancelHandler(() {
      if (mounted) setState(() => _isPlaying = false);
    });
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  void _togglePlayback() async {
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
                children: [
                  const Spacer(),
                  // Waveform — tap it to play/pause
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SiriWaveformVisualizer(
                      isPlaying: _isPlaying,
                      onTap: _togglePlayback,
                      amplitude: 3,
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
                  const Spacer(),
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
