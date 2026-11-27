import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/presentation/widgets/echo_button.dart';
import 'package:project_echo/core/services/voice/echo_voice.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_mascot.dart';
import 'package:project_echo/features/echo/presentation/widgets/siri_waveform_visualizer.dart';
import 'package:project_echo/features/onboarding/data/first_look.dart';
import 'package:project_echo/features/onboarding/data/first_look_source.dart';
import 'package:project_echo/features/onboarding/presentation/cubit/on_boarding_cubit.dart';
import 'package:project_echo/features/onboarding/presentation/widgets/onboarding_scaffold.dart';

/// Straight after access is granted, Echo looks at what's already on the
/// phone and reads the owner a short first look, out loud, in his voice
/// (the phone's until the natural one is downloaded). Built on the phone
/// from what was caught up, with no model, so it's there within seconds.
///
/// While the shade is caught up Echo listens; then his words play over the
/// waveform, with the counts beside them and the transcript below. Tapping
/// the wave stops or replays it.
class FirstLookScreen extends StatefulWidget {
  final bool autoPlay;

  /// Where the first look comes from; the phone's notifications in the app.
  final Future<FirstLook> Function() load;

  const FirstLookScreen({
    super.key,
    this.autoPlay = true,
    this.load = FirstLookSource.load,
  });

  @override
  State<FirstLookScreen> createState() => _FirstLookScreenState();
}

class _FirstLookScreenState extends State<FirstLookScreen> {
  final _voice = EchoVoice.instance;
  FirstLook? _look;
  bool _playing = false;
  bool _stopped = false;

  /// Echo listens for at least this long, so the step reads as a look
  /// rather than a flicker.
  static const _minimumLook = Duration(milliseconds: 1400);

  @override
  void initState() {
    super.initState();
    _voice.warmUp();
    _start();
  }

  Future<void> _start() async {
    final results = await Future.wait<Object?>([
      widget.load(),
      Future<void>.delayed(_minimumLook),
    ]);
    if (!mounted) return;
    setState(() => _look = results.first as FirstLook);
    if (widget.autoPlay) _play();
  }

  Future<void> _play() async {
    final look = _look;
    if (look == null) return;
    await _voice.stop();
    if (!mounted) return;
    setState(() {
      _playing = true;
      _stopped = false;
    });
    _voice.sayAll(look.text);
    await _voice.finished;
    if (!mounted) return;
    setState(() => _playing = false);
    // Heard to the end: the funnel's "first briefing heard".
    if (!_stopped) context.read<OnBoardingCubit>().firstLookHeard(look.kind);
  }

  Future<void> _toggle() async {
    HapticFeedback.lightImpact();
    if (_playing) {
      _stopped = true;
      await _voice.stop();
    } else {
      await _play();
    }
  }

  @override
  void dispose() {
    _voice.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final look = _look;
    final still = MediaQuery.disableAnimationsOf(context);
    final cubit = context.read<OnBoardingCubit>();

    return OnboardingStepBody(
      title: look == null
          ? 'Taking a first look…'
          : look.kind == FirstLookKind.empty
          ? 'All quiet, for now.'
          : 'Your first look.',
      subtitle: look == null
          ? 'Echo is reading what’s already in your notifications, right '
                'here on your phone.'
          : 'Read from what’s on your phone, on your phone. Tap the wave to '
                '${_playing ? 'stop' : 'hear it again'}.',
      scrollableBody: false,
      footer: EchoButton(
        text: 'Continue',
        showArrow: true,
        onPressed: look == null
            ? null
            : () {
                // Echo stops as the step leaves (see dispose).
                _stopped = true;
                cubit.completeFirstLook();
              },
      ),
      child: AnimatedSwitcher(
        duration: still ? Duration.zero : AppMotion.slow,
        switchInCurve: AppMotion.emphasized,
        switchOutCurve: AppMotion.standard,
        child: look == null
            ? const _Listening(key: ValueKey('listening'))
            : _Reading(
                key: const ValueKey('reading'),
                look: look,
                playing: _playing,
                still: still,
                onToggle: _toggle,
              ),
      ),
    );
  }
}

/// Echo listening while the shade is caught up.
class _Listening extends StatelessWidget {
  const _Listening({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: 'Echo is reading your notifications',
      child: const Column(
        children: [
          SizedBox(height: 24),
          Center(child: EchoMascot(state: EchoState.listening, size: 168)),
        ],
      ),
    );
  }
}

/// The first look itself: the wave Echo speaks over, what he counted, and
/// what he says.
class _Reading extends StatelessWidget {
  final FirstLook look;
  final bool playing;
  final bool still;
  final VoidCallback onToggle;

  const _Reading({
    super.key,
    required this.look,
    required this.playing,
    required this.still,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final facts = [
      if (look.notifications > 0)
        (
          Symbols.notifications_rounded,
          '${look.notifications}',
          look.notifications == 1 ? 'notification' : 'notifications',
        ),
      if (look.waiting.isNotEmpty)
        (Symbols.forum_rounded, '${look.waiting.length}', 'waiting on you'),
      if (look.comingUp > 0)
        (Symbols.event_upcoming_rounded, '${look.comingUp}', 'coming up'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          label: playing ? 'Stop Echo' : 'Hear the first look again',
          child: SiriWaveformVisualizer(
            // With animations off the wave stays a calm line.
            isPlaying: playing && !still,
            onTap: onToggle,
            amplitude: 3,
            height: 110,
          ),
        ),
        if (facts.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final (icon, value, label) in facts)
                _Fact(icon: icon, value: value, label: label),
            ],
          ),
        ],
        const SizedBox(height: 14),
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
                look.text,
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
    );
  }
}

/// One count, as a solid rounded chip: "3 waiting on you".
class _Fact extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _Fact({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      label: '$value $label',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: colors.primaryGreen, fill: 1),
            const SizedBox(width: 8),
            Text(
              value,
              style: GoogleFonts.oldStandardTt(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: GoogleFonts.nunito(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
