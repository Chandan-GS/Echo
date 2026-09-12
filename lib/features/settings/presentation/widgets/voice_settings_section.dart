import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_echo/core/services/echo_tts.dart';
import 'package:project_echo/core/services/voice_catalog.dart';
import 'package:project_echo/features/onboarding/data/voice_preference.dart';
import 'package:project_echo/features/onboarding/presentation/widgets/voice_studio.dart';

/// Settings ▸ Voice — lets the user re-tune the briefing voice (gender · accent ·
/// speed · character) at any time, using the same [VoiceStudio] surface as
/// onboarding. Self-contained: persists via [VoicePreference] (which also keeps
/// the shared `speech_rate` key in sync) and auditions changes live.
class VoiceSettingsSection extends StatefulWidget {
  const VoiceSettingsSection({super.key});

  @override
  State<VoiceSettingsSection> createState() => _VoiceSettingsSectionState();
}

class _VoiceSettingsSectionState extends State<VoiceSettingsSection> {
  final FlutterTts _tts = FlutterTts();
  VoicePreference _pref = VoicePreference.fallback;
  List<EchoAccent> _accents = EchoAccent.values;
  bool _playing = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    final prefs = await SharedPreferences.getInstance();
    final restored = VoicePreference.read(prefs);
    final accents = await VoiceCatalog.instance.availableAccents(_tts);

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
      _pref = accents.contains(restored.accent)
          ? restored
          : restored.copyWith(accent: accents.first);
      _accents = accents;
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

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await _pref.persist(prefs);
  }

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
    _persist();
    if (audition) _audition();
  }

  @override
  Widget build(BuildContext context) {
    return VoiceStudio(
      pref: _pref,
      accents: _accents,
      isPlaying: _playing,
      onTogglePlay: _togglePlay,
      onChanged: _update,
    );
  }
}
