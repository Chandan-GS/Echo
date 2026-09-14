import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
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
  List<Map<String, String>>? _installedVoices;
  bool _playing = false;
  bool _ready = false;
  bool _hasHighQualityVoice = true; // optimistic default — hides the hint

  bool get _isDesktop => Platform.isMacOS || Platform.isWindows;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup({bool rescan = false}) async {
    // Re-read from the device on an explicit rescan (or every open) so a voice
    // the user just installed in System Settings shows up without relaunching.
    if (rescan) VoiceCatalog.instance.invalidate();
    final prefs = await SharedPreferences.getInstance();
    final restored = VoicePreference.read(prefs);
    final accents = await VoiceCatalog.instance.availableAccents(_tts);
    final hasGoodVoice = await VoiceCatalog.instance.hasHighQualityVoice(_tts);
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
        if (!stillInstalled) _persist();
      } else {
        _pref = accents.contains(restored.accent)
            ? restored
            : restored.copyWith(accent: accents.first);
      }
      _accents = accents;
      _installedVoices = installedVoices;
      _hasHighQualityVoice = hasGoodVoice;
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (Platform.isMacOS && !_hasHighQualityVoice) const _BetterVoicesHint(),
        if (_isDesktop)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _RescanButton(onTap: () => _setup(rescan: true)),
          ),
        VoiceStudio(
          pref: _pref,
          accents: _accents,
          isPlaying: _playing,
          onTogglePlay: _togglePlay,
          onChanged: _update,
          installedVoices: _installedVoices,
        ),
      ],
    );
  }
}

/// A quiet "rescan the system for newly installed voices" affordance. macOS
/// only surfaces a freshly downloaded voice to a process that re-queries, so
/// after installing a Premium voice the user taps this instead of relaunching.
class _RescanButton extends StatelessWidget {
  final VoidCallback onTap;
  const _RescanButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.refresh_rounded, size: 16, color: colors.primaryGreen),
                const SizedBox(width: 8),
                Text(
                  'Rescan installed voices',
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
      ),
    );
  }
}

/// macOS ships every built-in voice at its lowest ("default") quality tier —
/// genuinely natural "Enhanced"/"Premium" voices exist for free, but only
/// once the user downloads them via System Settings. Echo already prefers
/// them automatically the moment they're installed (see VoiceCatalog); this
/// just tells people where to get them. Critically it also warns that Siri's
/// own voice can NOT be used — Apple hides it from every third-party app (and
/// even from the `say` command), so a user who picks a "Siri voice" as their
/// System Voice just hears a silent fallback. Steer them to a Premium voice
/// instead. No deep-link button — the exact System Settings pane/bundle ID
/// changes across macOS versions, so a plain, always-correct path is more
/// reliable than a link that might silently 404.
class _BetterVoicesHint extends StatelessWidget {
  const _BetterVoicesHint();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.lightGreenBackground.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.primaryGreen.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.record_voice_over_rounded, size: 18, color: colors.primaryGreen),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: GoogleFonts.nunito(fontSize: 12.5, height: 1.45, color: colors.textPrimary),
                children: [
                  const TextSpan(
                    text: 'These are macOS\'s default-quality voices. For much more '
                        'natural speech, download a free ',
                  ),
                  TextSpan(
                    text: 'Premium',
                    style: GoogleFonts.nunito(fontSize: 12.5, fontWeight: FontWeight.w800),
                  ),
                  const TextSpan(text: ' (or Enhanced) voice in '),
                  TextSpan(
                    text: 'System Settings → Accessibility → Spoken Content → '
                        'System Voice → Manage Voices',
                    style: GoogleFonts.nunito(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: colors.primaryGreen,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => _openSystemSettings(),
                  ),
                  const TextSpan(
                    text: ', then tap Rescan. Note: ',
                  ),
                  TextSpan(
                    text: 'Siri\'s own voice can\'t be used',
                    style: GoogleFonts.nunito(fontSize: 12.5, fontWeight: FontWeight.w800),
                  ),
                  const TextSpan(
                    text: ' — Apple locks it to Siri, so pick a Premium voice instead.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openSystemSettings() async {
    // Opens System Settings to its default landing pane — reliable across
    // macOS versions, unlike deep-linking a specific pane/bundle ID.
    final uri = Uri.parse('x-apple.systempreferences:');
    try {
      await launchUrl(uri);
    } catch (_) {
      // Best-effort only — the instructions above are the source of truth.
    }
  }
}
