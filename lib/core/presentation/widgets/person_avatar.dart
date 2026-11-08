import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/services/person_photos.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/vault/presentation/widgets/source_icon.dart';

/// A person's face in Echo: their initial on a tint that stays the same for
/// that name, the app they wrote on as a small badge, and, when it's given,
/// a ring that fills and warms as they wait.
class PersonAvatar extends StatelessWidget {
  final String name;
  final double size;

  /// The app behind them (a [RawData.source]). No badge when null.
  final String? source;

  /// How long they've waited: [age] 0 is green, 1 amber, 2 rust; [progress]
  /// is how much of the ring is filled, 0 to 1.
  final ({int age, double progress})? ring;

  const PersonAvatar({
    super.key,
    required this.name,
    required this.size,
    this.source,
    this.ring,
  });

  static const _tints = [
    Color(0xFF7C6BB0),
    Color(0xFF3E8E7E),
    Color(0xFFC2703D),
    Color(0xFF4F7CB4),
    Color(0xFFB0527A),
    Color(0xFF5E8F4E),
    Color(0xFF6B6F7A),
    Color(0xFF9A7B3E),
    Color(0xFFA8604F),
  ];

  static const _ringGap = 3.0;

  /// The same name always lands on the same tint, on any run (String's own
  /// hashCode isn't stable between runs).
  static Color _tintFor(String name) {
    var hash = 0x811C9DC5;
    for (final unit in name.trim().toLowerCase().codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
    return _tints[hash % _tints.length];
  }

  static final _letter = RegExp(r'[\p{L}\p{N}]', unicode: true);

  /// The first letter or digit, whatever the script, so "🔥 Rohan" is R and
  /// "प्रिया" keeps its whole first cluster. An all-emoji name shows the
  /// emoji; an empty one a question mark.
  static String _initial(String name) {
    final characters = name.trim().characters;
    for (final c in characters) {
      if (_letter.hasMatch(c)) return c.toUpperCase();
    }
    return characters.isEmpty ? '?' : characters.first;
  }

  @override
  Widget build(BuildContext context) {
    final ring = this.ring;
    final inset = ring == null ? 0.0 : _ringGap;
    final badge = (size * 0.38).roundToDouble();
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (ring != null)
            Positioned.fill(
              child: CustomPaint(
                painter: _RingPainter(
                  color: _ringColor(context, ring.age),
                  track: context.colors.textPrimary.withValues(alpha: 0.1),
                  progress: ring.progress,
                ),
              ),
            ),
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.all(inset),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _tintFor(name),
                  shape: BoxShape.circle,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: Text(
                        _initial(name),
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        // Sized to the circle, not to the reader's text scale.
                        textScaler: TextScaler.noScaling,
                        style: GoogleFonts.nunito(
                          fontSize: (size * 0.36).roundToDouble(),
                          fontWeight: FontWeight.w800,
                          height: 1,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    _Photo(name: name, source: source, size: size - inset * 2),
                  ],
                ),
              ),
            ),
          ),
          if (source != null && source!.trim().isNotEmpty)
            Positioned(
              right: -3,
              bottom: -3,
              child: _AppBadge(source: source!, size: badge),
            ),
        ],
      ),
    );
  }

  static Color _ringColor(BuildContext context, int age) {
    final dark = context.isDarkMode;
    return switch (age) {
      <= 0 => dark ? const Color(0xFF6EBC76) : const Color(0xFF49884F),
      1 => dark ? const Color(0xFFE6C77A) : const Color(0xFFC9962E),
      _ => dark ? const Color(0xFFE58C76) : const Color(0xFFC0503B),
    };
  }
}

/// Their real picture, over the initial. Until it's known, and if it can
/// ever not be painted, the initial underneath is what shows.
class _Photo extends StatelessWidget {
  final String name;
  final String? source;
  final double size;

  const _Photo({required this.name, required this.source, required this.size});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PersonPhoto>(
      valueListenable: PersonPhotos.watch(name, source),
      builder: (context, photo, _) {
        final path = photo.path;
        if (path == null) return const SizedBox.shrink();
        final cacheWidth = (size * MediaQuery.devicePixelRatioOf(context))
            .ceil()
            .clamp(1, 288);
        return ClipOval(
          child: Image(
            image: PersonPhotos.providerFor(path, cacheWidth),
            width: size,
            height: size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded) return child;
              return AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: AppMotion.fast,
                curve: AppMotion.standard,
                child: child,
              );
            },
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}

/// The app's real icon, cut out of the avatar by a ring of the card's colour.
class _AppBadge extends StatelessWidget {
  final String source;
  final double size;

  const _AppBadge({required this.source, required this.size});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: size + 4,
      height: size + 4,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.surface, shape: BoxShape.circle),
      child: ClipOval(
        child: SourceIcon(
          source: source,
          size: size,
          fallback: SizedBox.square(
            dimension: size,
            child: ColoredBox(
              color: c.dividerColor,
              child: Icon(
                Symbols.apps_rounded,
                size: size * 0.7,
                color: c.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A thin ring around the edge of the avatar, filling clockwise from the top.
class _RingPainter extends CustomPainter {
  final Color color;
  final Color track;
  final double progress;

  const _RingPainter({
    required this.color,
    required this.track,
    required this.progress,
  });

  static const _stroke = 1.25;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(_stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    final sweep = progress.clamp(0.0, 1.0) * math.pi * 2;
    if (sweep > 0) {
      canvas.drawArc(rect, -math.pi / 2, sweep, false, paint..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.color != color || old.track != track || old.progress != progress;
}
