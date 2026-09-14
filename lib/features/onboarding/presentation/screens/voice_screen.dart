import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_echo/core/presentation/widgets/echo_button.dart';
import 'package:project_echo/core/services/echo_tts.dart';
import 'package:project_echo/core/services/voice_catalog.dart';
import 'package:project_echo/features/onboarding/data/voice_preference.dart';
import 'package:project_echo/features/onboarding/presentation/cubit/on_boarding_cubit.dart';
import 'package:project_echo/features/onboarding/presentation/widgets/onboarding_scaffold.dart';
import 'package:project_echo/features/onboarding/presentation/widgets/voice_studio.dart';

/// Step 5 — the user shapes their own voice (gender · accent · speed · pitch),
/// auditioning live. Curated presets give a one-tap starting point.
class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key});

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> {
  final FlutterTts _tts = FlutterTts();
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
    final accents = await VoiceCatalog.instance.availableAccents(_tts);
    final installedVoices =
        _isDesktop ? await VoiceCatalog.instance.listInstalledVoices(_tts) : null;

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
        final stillInstalled = restored.hasDirectVoice &&
            installedVoices.any((v) =>
                v['name'] == restored.directVoiceName &&
                v['locale'] == restored.directVoiceLocale);
        _pref = stillInstalled
            ? restored
            : (installedVoices.isNotEmpty
                ? restored.withDirectVoice(
                    name: installedVoices.first['name']!,
                    locale: installedVoices.first['locale']!,
                  )
                : restored);
      } else {
        // Keep an accent that actually exists on the device selected.
        _pref = accents.contains(restored.accent)
            ? restored
            : restored.copyWith(accent: accents.first);
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
    super.dispose();
  }

  /// Applies the current preference and speaks the audition line.
  Future<void> _audition() async {
    if (!_ready) return;
    try {
      await _tts.stop();
      await EchoTts.applyPreference(_tts, _pref);
      if (mounted) setState(() => _playing = true);
      await _tts.speak(_pref.previewLine);
    } catch (_) {
      if (mounted) setState(() => _playing = false);
    }
  }

  Future<void> _togglePlay() async {
    if (_playing) {
      await _tts.stop();
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
      subtitle: 'Tune it until it feels right. Every change plays instantly.',
      footer: EchoButton(
        text: 'Continue',
        showArrow: true,
        onPressed: () async {
          await _tts.stop();
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
      ),
    );
  }
}
