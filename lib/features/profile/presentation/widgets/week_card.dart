import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_icon_art.dart';
import 'package:project_echo/features/profile/data/week_card.dart';

/// The shareable week card: Echo's dark canvas with a green glow, the
/// week's headline count in Old Standard TT, the other counts beneath it,
/// Echo's green waveform, and the listing's name at the foot.
///
/// It only ever draws what [WeekCardData] holds — counts, never anyone's
/// messages. It's drawn at a fixed [size] (4:5, the shape feeds and chats
/// show whole) and scales its contents down rather than overflowing when
/// the text is large.
class WeekCard extends StatelessWidget {
  final WeekCardData data;
  const WeekCard({super.key, required this.data});

  static const _w = 360.0, _h = 450.0;
  static const size = Size(_w, _h);
  static const _pad = 28.0;

  static const _ground = AppTheme.backgroundDark;
  static const _green = AppTheme.primaryGreenDark;
  static const _text = AppTheme.textPrimaryDark;
  static const _muted = AppTheme.textSecondaryDark;

  @override
  Widget build(BuildContext context) {
    const inner = Size(_w - 2 * _pad, _h - 2 * _pad);
    return SizedBox.fromSize(
      size: size,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: _ground,
          gradient: RadialGradient(
            center: Alignment(0.9, -0.95),
            radius: 1.25,
            colors: [AppTheme.darkGreenBackground, _ground],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(_pad),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: inner.width,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: inner.height),
                child: IntrinsicHeight(child: _content()),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content() {
    final stats = data.stats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const ClipOval(child: EchoIconArt(size: 30)),
            const SizedBox(width: 10),
            Text(
              'Echo',
              style: GoogleFonts.oldStandardTt(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _text,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                data.range,
                textAlign: TextAlign.end,
                style: GoogleFonts.nunito(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: _muted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        Text(
          'MY WEEK',
          style: GoogleFonts.nunito(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.2,
            color: _green,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          data.headline,
          style: GoogleFonts.oldStandardTt(
            fontSize: 29,
            fontWeight: FontWeight.w700,
            height: 1.16,
            color: _text,
          ),
        ),
        const SizedBox(height: 22),
        for (final (i, (value, label)) in stats.indexed) ...[
          if (i > 0) const SizedBox(height: 12),
          // A long label goes under its number rather than off the edge.
          Wrap(
            spacing: 10,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              Text(
                value,
                style: GoogleFonts.nunito(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: _green,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  label,
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _muted,
                  ),
                ),
              ),
            ],
          ),
        ],
        const Spacer(),
        const SizedBox(height: 18),
        const SizedBox(
          height: 56,
          width: double.infinity,
          child: CustomPaint(painter: _WavePainter()),
        ),
        const SizedBox(height: 14),
        Text(
          WeekCardData.appTitle,
          style: GoogleFonts.nunito(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: _text,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          WeekCardData.storeLine,
          style: GoogleFonts.nunito(fontSize: 12.5, color: _muted),
        ),
      ],
    );
  }
}

/// Echo's voice line, still: a few soft green sine strands, fading at the
/// edges, as the Siri-style waveform looks mid-word.
class _WavePainter extends CustomPainter {
  const _WavePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    const strands = [(1.0, 0.0, 0.55), (0.7, 1.3, 0.32), (0.45, 2.4, 0.2)];
    for (final (amp, phase, alpha) in strands) {
      final path = Path();
      for (var x = 0.0; x <= size.width; x += 2) {
        final t = x / size.width;
        // Quiet at the edges, loudest in the middle.
        final envelope = math.sin(math.pi * t);
        final y =
            mid +
            math.sin(t * math.pi * 5 + phase) *
                envelope *
                amp *
                size.height *
                0.42;
        x == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..color = AppTheme.primaryGreenDark.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) => false;
}

/// Profile's "Share my week": a quiet tonal pill under the week's numbers.
/// Profile shows it only when [WeekCardData.worthSharing].
class ShareWeekButton extends StatelessWidget {
  /// Null while the card is being drawn, which disables it.
  final VoidCallback? onPressed;
  const ShareWeekButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Align(
        child: TextButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.ios_share_rounded, size: 19),
          label: Text(
            'Share my week',
            style: GoogleFonts.nunito(
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          style: TextButton.styleFrom(
            foregroundColor: c.primaryGreen,
            backgroundColor: c.primaryGreen.withValues(
              alpha: context.isDarkMode ? 0.16 : 0.12,
            ),
            minimumSize: const Size(kMinInteractiveDimension, 48),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            shape: const StadiumBorder(),
          ),
        ),
      ),
    );
  }
}
