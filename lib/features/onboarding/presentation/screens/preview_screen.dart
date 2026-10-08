import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/core/presentation/widgets/echo_button.dart';
import 'package:project_echo/core/services/voice/echo_voice.dart';
import 'package:project_echo/core/services/voice/natural_voice.dart';
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
  final _voice = EchoVoice.instance;
  late final String _sample;
  bool _isPlaying = false;

  /// Whether the natural voice is downloaded; until then Echo reads with the
  /// phone's own voice, and the screen says so.
  bool _natural = true;

  @override
  void initState() {
    super.initState();
    _sample = buildSampleBriefing(
      name: widget.name,
      tone: widget.tone,
      interests: widget.interests,
    );
    _voice.speaking.addListener(_onSpeaking);
    // A download still going from the voice step can finish here.
    NaturalVoice.instance.changed.addListener(_checkNatural);
    NaturalVoice.instance.installing.addListener(_onInstalling);
    _start();
  }

  Future<void> _start() async {
    await _checkNatural();
    if (mounted) _speak(); // auto-play the "aha" moment once
  }

  /// The voice just chosen is saved, so Echo speaks with exactly it.
  Future<void> _checkNatural() async {
    final natural =
        Platform.isMacOS ||
        Platform.isWindows ||
        await NaturalVoice.instance.modelDir(widget.voice) != null;
    if (mounted) setState(() => _natural = natural);
  }

  void _onInstalling() {
    if (mounted) setState(() {});
  }

  bool get _downloading =>
      NaturalVoice.instance.installing.value == piperVoice(widget.voice);

  void _onSpeaking() {
    final playing = _voice.speaking.value != null;
    if (mounted && playing != _isPlaying) {
      setState(() => _isPlaying = playing);
    }
  }

  Future<void> _speak() async {
    await _voice.stop();
    _voice.sayAll(_sample);
  }

  Future<void> _toggle() async {
    if (_isPlaying) {
      await _voice.stop();
    } else {
      await _speak();
    }
  }

  @override
  void dispose() {
    _voice.speaking.removeListener(_onSpeaking);
    NaturalVoice.instance.changed.removeListener(_checkNatural);
    NaturalVoice.instance.installing.removeListener(_onInstalling);
    _voice.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cubit = context.read<OnBoardingCubit>();

    return OnboardingStepBody(
      title: 'Here’s a taste.',
      subtitle: _natural
          ? 'This is your morning briefing, in your voice. Tap the wave to replay.'
          : _downloading
          ? 'This is your morning briefing, read by your phone’s voice while '
                '${widget.voice.voice.label} downloads. Tap the wave to replay.'
          : 'This is your morning briefing, read by your phone’s voice until you '
                'download ${widget.voice.voice.label} in Settings → Voice. Tap '
                'the wave to replay.',
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
