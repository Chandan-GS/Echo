import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_echo/core/presentation/widgets/echo_button.dart';
import 'package:project_echo/core/services/echo_tts.dart';
import 'package:project_echo/core/services/voice/natural_voice.dart';
import 'package:project_echo/core/services/voice_catalog.dart';
import 'package:project_echo/features/onboarding/data/voice_preference.dart';
import 'package:project_echo/features/onboarding/presentation/cubit/on_boarding_cubit.dart';
import 'package:project_echo/features/onboarding/presentation/widgets/onboarding_scaffold.dart';
import 'package:project_echo/features/onboarding/presentation/widgets/voice_studio.dart';
import 'package:project_echo/features/settings/presentation/widgets/natural_voice_tile.dart';

/// Step 5: the owner picks Echo's voice and pace, hearing each change.
///
/// On the phone these are Echo's natural (Piper) voices, heard from a short
/// bundled sample of each, so nothing is downloaded to choose one. The voice
/// itself is downloaded only if the owner asks, here or later in Settings.
/// The desktop picks one of the computer's own voices instead.
class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key});

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> {
  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _sample = AudioPlayer();
  StreamSubscription<void>? _sampleEnded;
  VoicePreference _pref = VoicePreference.fallback;
  List<EchoAccent> _accents = EchoAccent.values;
  List<Map<String, String>>? _installedVoices;
  bool _playing = false;
  bool _ready = false;

  bool get _isDesktop => Platform.isMacOS || Platform.isWindows;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    final prefs = await SharedPreferences.getInstance();
    final restored = VoicePreference.read(prefs);
    final accents = _isDesktop
        ? await VoiceCatalog.instance.availableAccents(_tts)
        : piperAccents;
    final installedVoices = _isDesktop
        ? await VoiceCatalog.instance.listInstalledVoices(_tts)
        : null;

    _sampleEnded = _sample.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _playing = false);
    });
    _tts.setCancelHandler(() {
      if (mounted) setState(() => _playing = false);
    });
    _tts.setErrorHandler((_) {
      if (mounted) setState(() => _playing = false);
    });

    if (!mounted) return;
    setState(() {
      if (installedVoices != null) {
        // Desktop: pick a specific installed device voice directly. Keep the
        // saved choice if it's still installed; otherwise default to the
        // best-quality one available.
        final stillInstalled =
            restored.hasDirectVoice &&
            installedVoices.any(
              (v) =>
                  v['name'] == restored.directVoiceName &&
                  v['locale'] == restored.directVoiceLocale,
            );
        _pref = stillInstalled
            ? restored
            : (installedVoices.isNotEmpty
                  ? restored.withDirectVoice(
                      name: installedVoices.first['name']!,
                      locale: installedVoices.first['locale']!,
                    )
                  : restored);
      } else {
        // The accent the natural voices speak it in.
        _pref = restored.copyWith(accent: piperAccent(restored.accent));
      }
      _accents = accents;
      _installedVoices = installedVoices;
      _ready = true;
    });
  }

  @override
  void dispose() {
    _tts.setCompletionHandler(() {});
    _tts.setCancelHandler(() {});
    _tts.setErrorHandler((_) {});
    _tts.stop();
    _sampleEnded?.cancel();
    _sample.dispose();
    super.dispose();
  }

  /// Plays the chosen voice's hello: its sample on the phone, the computer's
  /// own voice on the desktop.
  Future<void> _audition() async {
    if (!_ready) return;
    try {
      await _stop();
      if (mounted) setState(() => _playing = true);
      if (_isDesktop) {
        await EchoTts.applyPreference(_tts, _pref);
        await _tts.speak(_pref.previewLine);
      } else {
        await _sample.setPlaybackRate(voiceSampleRate(_pref));
        await _sample.play(AssetSource(voiceSampleAsset(_pref)));
      }
    } catch (_) {
      if (mounted) setState(() => _playing = false);
    }
  }

  Future<void> _stop() async {
    await _tts.stop();
    await _sample.stop();
  }

  Future<void> _togglePlay() async {
    if (_playing) {
      await _stop();
      if (mounted) setState(() => _playing = false);
    } else {
      await _audition();
    }
  }

  void _update(VoicePreference next, {bool audition = true}) {
    setState(() => _pref = next);
    if (audition) _audition();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<OnBoardingCubit>();

    return OnboardingStepBody(
      title: 'Shape how Echo sounds.',
      subtitle: _isDesktop
          ? 'Tune it until it feels right. Every change plays instantly.'
          : 'Pick a voice and a pace. Every change plays instantly.',
      footer: EchoButton(
        text: 'Continue',
        showArrow: true,
        onPressed: () async {
          await _stop();
          cubit.completeVoice(_pref);
        },
      ),
      child: VoiceStudio(
        pref: _pref,
        accents: _accents,
        isPlaying: _playing,
        onTogglePlay: _togglePlay,
        onChanged: _update,
        installedVoices: _installedVoices,
        // Hearing the sample costs nothing; the voice itself is downloaded
        // only from here (or Settings), when the owner chooses to.
        footer: _isDesktop ? null : NaturalVoiceTile(pref: _pref),
      ),
    );
  }
}
