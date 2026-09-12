import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/core/presentation/widgets/echo_button.dart';
import 'package:project_echo/core/services/echo_tts.dart';
import 'package:project_echo/features/echo/presentation/widgets/siri_waveform_visualizer.dart';
import 'package:project_echo/features/onboarding/data/onboarding_personalization.dart';
import 'package:project_echo/features/onboarding/data/voice_preference.dart';
import 'package:project_echo/features/onboarding/presentation/cubit/on_boarding_cubit.dart';
import 'package:project_echo/features/onboarding/presentation/widgets/onboarding_scaffold.dart';

class PreviewScreen extends StatefulWidget {
  final String name;
  final OnboardingTone tone;
  final Set<OnboardingInterest> interests;
  final VoicePreference voice;

  const PreviewScreen({
    super.key,
    required this.name,
    required this.tone,
    required this.interests,
    required this.voice,
  });

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  final FlutterTts _tts = FlutterTts();
  late final String _sample;
  bool _isPlaying = false;
  bool _ttsReady = false;

  @override
  void initState() {
    super.initState();
    _sample = buildSampleBriefing(
      name: widget.name,
      tone: widget.tone,
      interests: widget.interests,
    );
    _setupTts();
  }

  Future<void> _setupTts() async {
    // Apply the exact voice the user just shaped so the payoff matches.
    await EchoTts.applyPreference(_tts, widget.voice);

    _tts.setStartHandler(() {
      if (mounted) setState(() => _isPlaying = true);
    });
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _isPlaying = false);
    });
    _tts.setCancelHandler(() {
      if (mounted) setState(() => _isPlaying = false);
    });
    _tts.setErrorHandler((_) {
      if (mounted) setState(() => _isPlaying = false);
    });

    if (!mounted) return;
    setState(() => _ttsReady = true);
    _speak(); // auto-play the "aha" moment once
  }

  Future<void> _speak() async {
    if (!_ttsReady) return;
    try {
      await _tts.stop();
      await _tts.speak(_sample);
    } catch (_) {}
  }

  Future<void> _toggle() async {
    if (_isPlaying) {
      await _tts.stop();
      if (mounted) setState(() => _isPlaying = false);
    } else {
      await _speak();
    }
  }

  @override
  void dispose() {
    _tts.setStartHandler(() {});
    _tts.setCompletionHandler(() {});
    _tts.setCancelHandler(() {});
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cubit = context.read<OnBoardingCubit>();

    return OnboardingStepBody(
      title: 'Here’s a taste.',
      subtitle:
          'This is your morning briefing, in your voice. Tap the wave to replay.',
      scrollableBody: false,
      footer: EchoButton(
        text: 'Sounds great — finish setup',
        onPressed: () {
          HapticFeedback.mediumImpact(); // milestone: setup complete
          cubit.finishOnboarding();
        },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SiriWaveformVisualizer(
            isPlaying: _isPlaying,
            onTap: _toggle,
            amplitude: 3,
            height: 130,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: colors.lightGreenBackground.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: colors.primaryGreen.withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  _sample,
                  style: GoogleFonts.nunito(
                    fontSize: 18,
                    height: 1.6,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
