import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_mascot.dart';

/// Sample notifications for [AccessPreview]: made up, the same for everyone.
const _samples = [
  (Symbols.chat_rounded, 'Rahul', 'Are we still on for 6 tonight?'),
  (Symbols.mail_rounded, 'Priya', 'Updated deck attached, have a look'),
  (Symbols.event_rounded, 'Standup', 'Moved to 11:00 AM'),
];

const _sampleLine =
    'Rahul’s waiting on you about 6 tonight, and standup moved to 11.';

/// On the access step, what Echo will do with access, before it's asked
/// for: three sample notifications land in a card, then Echo turns them
/// into one line, word by word. About five seconds, played once; tap to
/// play it again. With animations off it shows the finished card.
class AccessPreview extends StatefulWidget {
  const AccessPreview({super.key});

  @override
  State<AccessPreview> createState() => _AccessPreviewState();
}

class _AccessPreviewState extends State<AccessPreview>
    with SingleTickerProviderStateMixin {
  /// The storyboard, in seconds.
  static const _length = 5.0;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (_length * 1000).round()),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _c.value = 1;
      } else {
        _c.forward();
      }
    });
  }

  void _replay() {
    if (MediaQuery.disableAnimationsOf(context)) return;
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static double _span(double t, double a, double b) =>
      AppMotion.emphasized.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final words = _sampleLine.split(' ');
    return Semantics(
      label:
          'A sample of what Echo reads you. Three notifications: Rahul asks '
          'if you are still on for 6 tonight, Priya sent an updated deck, and '
          'standup moved to 11. Echo says: $_sampleLine',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: _replay,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(22),
          ),
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = _c.value * _length;
              final speaking = t > 2.3 && t < 4.7;
              // The notifications settle back once Echo starts talking.
              final dim = 1 - 0.45 * _span(t, 2.0, 2.6);
              final shown = (_span(t, 2.4, 4.6) * words.length).ceil();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'SAMPLE',
                        style: GoogleFonts.nunito(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                          color: colors.primaryGreen,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'What Echo will read you',
                        style: GoogleFonts.nunito(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  for (var i = 0; i < _samples.length; i++)
                    _SampleRow(
                      sample: _samples[i],
                      progress: _span(t, 0.2 + i * 0.5, 0.8 + i * 0.5),
                      dim: dim,
                    ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Opacity(
                        opacity: _span(t, 1.9, 2.4),
                        child: EchoMascot(
                          state: speaking ? EchoState.speaking : EchoState.idle,
                          size: 44,
                          showRings: false,
                          glow: false,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text.rich(
                            TextSpan(
                              children: [
                                for (var i = 0; i < words.length; i++)
                                  TextSpan(
                                    text: '${words[i]} ',
                                    style: TextStyle(
                                      color: i < shown
                                          ? colors.textPrimary
                                          : Colors.transparent,
                                    ),
                                  ),
                              ],
                            ),
                            style: GoogleFonts.oldStandardTt(
                              fontSize: 19,
                              height: 1.35,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// One sample notification, sliding up into place as [progress] runs.
class _SampleRow extends StatelessWidget {
  final (IconData, String, String) sample;
  final double progress;
  final double dim;

  const _SampleRow({
    required this.sample,
    required this.progress,
    required this.dim,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (icon, from, text) = sample;
    return Opacity(
      opacity: progress * dim,
      child: Transform.translate(
        offset: Offset(0, 10 * (1 - progress)),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: colors.lightGreenBackground.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: colors.primaryGreen, fill: 1),
              const SizedBox(width: 10),
              Text(
                from,
                style: GoogleFonts.nunito(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
