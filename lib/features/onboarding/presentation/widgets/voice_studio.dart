import 'dart:io';
import 'package:flutter/material.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/core/presentation/widgets/wave_slider.dart';
import 'package:project_echo/features/echo/presentation/widgets/siri_waveform_visualizer.dart';
import 'package:project_echo/features/onboarding/data/voice_preference.dart';
import 'package:project_echo/features/onboarding/presentation/widgets/selectable_tile.dart';

/// Live preview + control surface for shaping a [VoicePreference]: pick one of
/// four voices (Aria, Sage, Atlas, Nova), choose an accent, and set the pace.
///
/// Purely presentational — the parent owns TTS and applies/auditions in response
/// to [onChanged] / [onTogglePlay].
class VoiceStudio extends StatelessWidget {
  final VoicePreference pref;
  final List<EchoAccent> accents;
  final bool isPlaying;
  final VoidCallback onTogglePlay;
  final void Function(VoicePreference next, {bool audition}) onChanged;

  /// Desktop only — the real installed system voices (name/locale/quality),
  /// already loaded by the parent. When non-null, the Voice/Accent pickers
  /// are replaced with a direct list of these, since desktop has actual named
  /// system voices instead of the phone's curated four-slot abstraction. Null
  /// on phone (and on desktop while still loading).
  final List<Map<String, String>>? installedVoices;

  const VoiceStudio({
    super.key,
    required this.pref,
    required this.accents,
    required this.isPlaying,
    required this.onTogglePlay,
    required this.onChanged,
    this.installedVoices,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDesktop = Platform.isMacOS || Platform.isWindows;
    final voices = installedVoices;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Live preview (gradient hero card, matching the streak widget) ──
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colors.primaryGreen,
                Color.lerp(colors.primaryGreen, Colors.black, 0.42)!,
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: colors.primaryGreen.withValues(alpha: 0.28),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              SiriWaveformVisualizer(
                isPlaying: isPlaying,
                onTap: onTogglePlay,
                amplitude: 2.5,
                height: 78,
                color1: Colors.white,
                color2: Colors.white.withValues(alpha: 0.55),
                color3: Colors.white.withValues(alpha: 0.85),
              ),
              const SizedBox(height: 6),
              _PlayButton(isPlaying: isPlaying, onTap: onTogglePlay),
            ],
          ),
        ),
        const SizedBox(height: 26),

        if (isDesktop && voices != null) ...[
          // ── Desktop: one real, named system voice ──────────────────────
          const _Label('System voice'),
          const SizedBox(height: 12),
          _InstalledVoiceList(pref: pref, voices: voices, onChanged: onChanged),
          const SizedBox(height: 26),
        ] else ...[
          // ── Voice ─────────────────────────────────────────────────────
          const _Label('Voice'),
          const SizedBox(height: 12),
          _VoiceTiles(pref: pref, onChanged: onChanged),
          const SizedBox(height: 18),

          // ── Accent ────────────────────────────────────────────────────
          const _Label('Accent'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: accents
                .map((a) => _Choice(
                      label: a.label,
                      selected: pref.accent == a,
                      onTap: () => onChanged(pref.copyWith(accent: a)),
                    ))
                .toList(),
          ),
          const SizedBox(height: 26),
        ],

        // ── Speed ───────────────────────────────────────────────────────
        const _Label('Speed'),
        _TunerSlider(
          value: pref.speed,
          minLabel: 'Slower',
          maxLabel: 'Faster',
          onChanged: (v) => onChanged(pref.copyWith(speed: v), audition: false),
          onChangeEnd: (v) => onChanged(pref.copyWith(speed: v)),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Desktop's direct voice list — every usable system voice, by its real name,
/// single-select. Replaces the phone's voice-slot + accent pickers entirely:
/// desktop has actual named voices to choose from, so showing the abstraction
/// on top of them was just confusing (and hid genuinely installed voices).
class _InstalledVoiceList extends StatelessWidget {
  final VoicePreference pref;
  final List<Map<String, String>> voices;
  final void Function(VoicePreference next, {bool audition}) onChanged;

  const _InstalledVoiceList({
    required this.pref,
    required this.voices,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (voices.isEmpty) {
      return Text(
        'No system voices found.',
        style: GoogleFonts.nunito(fontSize: 13, color: context.colors.textSecondary),
      );
    }
    return Column(
      children: voices.map((v) {
        final name = v['name'] ?? '';
        final locale = v['locale'] ?? '';
        final quality = (v['quality'] ?? '').toLowerCase();
        final isBetter = quality == 'enhanced' || quality == 'premium';
        final selected = pref.directVoiceName == name && pref.directVoiceLocale == locale;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SelectableTile(
            title: name,
            subtitle: isBetter ? '$locale · ${_titleCase(quality)}' : locale,
            isSelected: selected,
            onTap: () => onChanged(
              pref.withDirectVoice(name: name, locale: locale),
            ),
          ),
        );
      }).toList(),
    );
  }

  String _titleCase(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

// ── Local building blocks ──────────────────────────────────────────────────

/// The four voice tiles. Stacked full-width on phone; a 2x2 wrap on desktop
/// so it reads as a set of cards rather than a tall phone list.
class _VoiceTiles extends StatelessWidget {
  final VoicePreference pref;
  final void Function(VoicePreference next, {bool audition}) onChanged;

  const _VoiceTiles({required this.pref, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    if (!(Platform.isMacOS || Platform.isWindows)) {
      return Column(
        children: EchoVoiceSlot.values
            .map(
              (v) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SelectableTile(
                  title: v.label,
                  isSelected: pref.voice == v,
                  onTap: () => onChanged(pref.copyWith(voice: v)),
                ),
              ),
            )
            .toList(),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 10.0;
        final itemWidth = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: EchoVoiceSlot.values
              .map(
                (v) => SizedBox(
                  width: itemWidth,
                  child: SelectableTile(
                    title: v.label,
                    isSelected: pref.voice == v,
                    onTap: () => onChanged(pref.copyWith(voice: v)),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: GoogleFonts.nunito(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.6,
        color: context.colors.textSecondary,
      ),
    );
  }
}

/// A solid, borderless selectable chip used for accents.
class _Choice extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: selected ? context.selectionFill : colors.surface,
      borderRadius: BorderRadius.circular(30),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          child: Text(
            label,
            style: GoogleFonts.nunito(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: selected ? context.onSelection : colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onTap;

  const _PlayButton({required this.isPlaying, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(30),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
                size: 20,
                color: Colors.white,
              ),
              const SizedBox(width: 6),
              Text(
                isPlaying ? 'Playing…' : 'Play sample',
                style: GoogleFonts.nunito(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A labelled 0..1 slider with min/max captions.
class _TunerSlider extends StatelessWidget {
  final double value;
  final String minLabel;
  final String maxLabel;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _TunerSlider({
    required this.value,
    required this.minLabel,
    required this.maxLabel,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        WaveSlider(
          value: value,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                minLabel,
                style: GoogleFonts.nunito(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
              Text(
                maxLabel,
                style: GoogleFonts.nunito(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
