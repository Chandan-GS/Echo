import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/core/presentation/widgets/echo_button.dart';
import 'package:project_echo/core/services/app_icon_service.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_mascot.dart';
import 'package:project_echo/features/onboarding/presentation/cubit/on_boarding_cubit.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The first screen: Echo wakes up. He's asleep, three of the phone's own
/// app icons pop up around him and drift into him, he wakes, bounces up
/// happily, rises to his place, and says hello with the name, the promise
/// and Get Started. About three seconds, all of it slow and eased.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

/// Apps whose icons might wake him, in order of preference; the first three
/// installed are used.
const _iconPackages = [
  'com.whatsapp',
  'com.google.android.gm',
  'com.google.android.apps.messaging',
  'com.Slack',
  'com.google.android.calendar',
  'com.instagram.android',
  'org.telegram.messenger',
];

/// Stand-ins when the phone can't show three real icons (or on desktop).
const _fallbackIcons = [
  Symbols.chat_bubble_rounded,
  Symbols.mail_rounded,
  Symbols.event_rounded,
];

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  static const _length = 3.0; // seconds

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
  );
  List<Uint8List?> _icons = const [null, null, null];

  @override
  void initState() {
    super.initState();
    _loadIcons();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // With animations turned off, start at the end.
      if (MediaQuery.of(context).disableAnimations) {
        _c.value = 1;
      } else {
        _c.forward();
      }
    });
  }

  Future<void> _loadIcons() async {
    final found = <Uint8List>[];
    for (final pkg in _iconPackages) {
      if (found.length == 3) break;
      try {
        final bytes = await AppIconService.iconForPackage(pkg);
        if (bytes != null) found.add(bytes);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _icons = [for (var i = 0; i < 3; i++) i < found.length ? found[i] : null];
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  // ── The storyboard, as functions of time (seconds) ────────────────────

  static double _smooth(double x) => x * x * (3 - 2 * x);
  static double _span(double t, double a, double b) =>
      _smooth(((t - a) / (b - a)).clamp(0.0, 1.0));
  static double _lerp(double a, double b, double x) => a + (b - a) * x;

  /// Settles from 0 to 1 over [a, b] with one soft overshoot.
  static double _settle(double t, double a, double b) {
    final x = ((t - a) / (b - a)).clamp(0.0, 1.0);
    return 1 - math.exp(-5 * x) * math.cos(6 * x);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: LayoutBuilder(
        builder: (context, box) => AnimatedBuilder(
          animation: _c,
          builder: (context, _) => _frame(context, box, _c.value * _length),
        ),
      ),
    );
  }

  Widget _frame(BuildContext context, BoxConstraints box, double t) {
    final w = math.min(box.maxWidth, 480.0);
    final h = box.maxHeight;

    // ── Echo ──
    final asleep = t < 1.2;
    final happy = t > 1.62 && t < 1.95;
    final rise = _settle(t, 2.0, 2.5);
    final size = w * 0.64 * _lerp(1, 0.84, rise);
    final centerY = h * _lerp(0.44, 0.27, rise);
    // A gentle stretch-and-hop as he wakes, and a small happy wiggle.
    final b = t > 1.58 && t < 2.1 ? math.sin((t - 1.58) / 0.52 * math.pi) : 0.0;
    final squash = t > 1.58 && t < 2.1
        ? 0.07 *
              math.sin((t - 1.58) / 0.52 * 2 * math.pi) *
              (1 - (t - 1.58) / 0.52)
        : 0.0;
    final wiggle = happy
        ? 0.07 * math.sin((t - 1.62) * 26) * (1 - _span(t, 1.62, 1.95))
        : 0.0;
    final hop = 10 * b;
    final brightness = _lerp(0.55, 1, _span(t, 1.1, 1.7));
    final glow = _lerp(0.18, 1, _span(t, 1.15, 1.8));
    // Taking the icons in: a brief extra glow.
    final absorb = (_span(t, 1.08, 1.2) - _span(t, 1.25, 1.65)).clamp(0.0, 1.0);
    final lookAt = t < 2.0
        ? const Offset(0, 0.15)
        : t < 2.6
        ? Offset.zero
        : Offset(0.15, _lerp(0, 0.9, _span(t, 2.6, 2.85)));
    final state = asleep
        ? EchoState.sleeping
        : happy
        ? EchoState.happy
        : EchoState.idle;
    final orbR = size * 0.311; // the orb's radius inside the canvas

    // ── The words and the button ──
    final wordIn = _span(t, 2.4, 2.7);
    final lineIn = _span(t, 2.52, 2.82);
    final buttonIn = _span(t, 2.62, 2.95);

    Widget up(double v, Widget child) => Opacity(
      opacity: v,
      child: Transform.translate(offset: Offset(0, (1 - v) * 16), child: child),
    );

    return Stack(
      children: [
        // Echo's glow.
        Positioned(
          left: box.maxWidth / 2 - orbR * 2.6,
          top: centerY - hop - orbR * 2.6,
          width: orbR * 5.2,
          height: orbR * 5.2,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(
                      0xFFD6EBDA,
                    ).withValues(alpha: 0.2 * glow + 0.25 * absorb),
                    const Color(0xFFD6EBDA).withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        // The icons that wake him, one after another.
        for (var i = 0; i < 3; i++)
          _icon(i, t, box.maxWidth / 2, centerY, orbR),
        // Echo himself: the app's own mascot.
        Positioned(
          left: box.maxWidth / 2 - size / 2,
          top: centerY - hop - size / 2,
          width: size,
          height: size,
          child: Opacity(
            opacity: brightness,
            child: Transform.rotate(
              angle: wiggle,
              child: Transform.scale(
                scaleX: 1 + squash,
                scaleY: 1 - squash,
                child: EchoMascot(
                  state: state,
                  size: size,
                  showRings: false,
                  glow: false,
                  lookAt: lookAt,
                ),
              ),
            ),
          ),
        ),
        // The words and Get Started.
        SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Spacer(),
                    up(
                      wordIn,
                      Text(
                        'Echo',
                        style: GoogleFonts.oldStandardTt(
                          fontSize: 80,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          height: 1.1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    up(
                      lineIn,
                      Text(
                        'Your day, briefed aloud each morning.\nPrivate, and entirely on your phone.',
                        style: GoogleFonts.nunito(
                          fontSize: 18,
                          height: 1.4,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    IgnorePointer(
                      ignoring: buttonIn < 0.5,
                      child: up(
                        buttonIn,
                        EchoButton(
                          text: 'Get Started',
                          backgroundColor: const Color(0xFFF4F2EE),
                          textColor: const Color(0xFF1E1E1E),
                          showArrow: true,
                          onPressed: () =>
                              context.read<OnBoardingCubit>().completeWelcome(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// One icon: pops up beside him, then drifts gently into him and fades.
  Widget _icon(int i, double t, double cx, double cy, double orbR) {
    const spots = [Offset(-1.3, -1.0), Offset(1.35, -0.6), Offset(-1.1, 0.95)];
    final a = 0.74 + i * 0.12;
    if (t < a || t > a + 0.62) return const SizedBox.shrink();
    final pop = _settle(t, a, a + 0.26);
    final drift = _span(t, a + 0.28, a + 0.56);
    final fade = 1 - _span(t, a + 0.46, a + 0.6);
    final size = 34.0 * pop * (1 - 0.75 * drift);
    final x = cx + _lerp(spots[i].dx * orbR, 0, drift);
    final y = cy + _lerp(spots[i].dy * orbR, 0, drift);
    final bytes = _icons[i];
    return Positioned(
      left: x - size / 2,
      top: y - size / 2,
      width: size,
      height: size,
      child: Opacity(
        opacity: fade.clamp(0.0, 1.0),
        child: bytes != null
            ? ClipOval(
                child: Image.memory(
                  bytes,
                  gaplessPlayback: true,
                  fit: BoxFit.cover,
                ),
              )
            : DecoratedBox(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF2E2E2E),
                ),
                child: Icon(
                  _fallbackIcons[i],
                  size: size * 0.55,
                  color: const Color(0xFFAECFB4),
                ),
              ),
      ),
    );
  }
}
