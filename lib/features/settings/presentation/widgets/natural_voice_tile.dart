import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/services/voice/echo_voice.dart';
import 'package:project_echo/core/services/voice/natural_voice.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/onboarding/data/voice_preference.dart';

/// Echo's natural voice: a download that makes him sound like a person
/// rather than the phone's reader. Without it, the phone's voice is used.
class NaturalVoiceTile extends StatefulWidget {
  /// The voice the owner has chosen; each has its own download.
  final VoicePreference pref;
  const NaturalVoiceTile({super.key, required this.pref});

  @override
  State<NaturalVoiceTile> createState() => _NaturalVoiceTileState();
}

class _NaturalVoiceTileState extends State<NaturalVoiceTile> {
  final _voice = NaturalVoice.instance;

  /// Whether this tile's voice is downloaded.
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _check();
    _voice.changed.addListener(_check);
    EchoVoice.instance.warmUp();
  }

  @override
  void didUpdateWidget(NaturalVoiceTile old) {
    super.didUpdateWidget(old);
    // Another voice or accent: is that one downloaded?
    if (piperVoice(old.pref) != piperVoice(widget.pref)) _check();
  }

  @override
  void dispose() {
    _voice.changed.removeListener(_check);
    super.dispose();
  }

  Future<void> _check() async {
    final voice = piperVoice(widget.pref);
    final ready = await _voice.modelDir(widget.pref) != null;
    // Only if it's still this voice the tile shows.
    if (mounted && voice == piperVoice(widget.pref)) {
      setState(() => _ready = ready);
    }
  }

  Future<void> _install() async {
    try {
      await _voice.install(widget.pref);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "The natural voice didn't download. Try again on Wi-Fi.",
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.dividerColor.withValues(alpha: 0.6)),
      ),
      child: ListenableBuilder(
        listenable: Listenable.merge([_voice.installing, _voice.progress]),
        builder: (context, _) {
          final installed = _ready;
          // Progress only for this voice; another's download is replaced by
          // this one's if Download is tapped here.
          final mine = _voice.installing.value == piperVoice(widget.pref);
          final progress = mine ? _voice.progress.value : null;
          return Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Natural voice',
                      style: GoogleFonts.nunito(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      progress == null
                          ? (installed
                                ? '${widget.pref.voice.label} speaks with it, on '
                                      'your phone.'
                                : 'A more human ${widget.pref.voice.label} that '
                                      'runs on your phone. '
                                      '${NaturalVoice.downloadLabel} download.')
                          : progress < 0.9
                          ? 'Downloading · ${(progress / 0.9 * 100).round()}%'
                          : 'Unpacking…',
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        height: 1.4,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (progress != null)
                IconButton(
                  tooltip: 'Cancel',
                  onPressed: _voice.cancelInstall,
                  icon: Icon(
                    Symbols.close_rounded,
                    color: colors.textSecondary,
                  ),
                )
              else if (installed)
                TextButton(
                  onPressed: _voice.remove,
                  child: Text(
                    'Remove',
                    style: GoogleFonts.nunito(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: colors.textSecondary,
                    ),
                  ),
                )
              else
                FilledButton(
                  onPressed: _install,
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.textPrimary,
                    foregroundColor: colors.background,
                    shape: const StadiumBorder(),
                  ),
                  child: Text(
                    'Download',
                    style: GoogleFonts.nunito(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
