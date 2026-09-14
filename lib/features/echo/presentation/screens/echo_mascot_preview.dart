import 'package:flutter/material.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_mascot.dart';

/// Debug-only gallery of every [EchoState] so the mascot can be reviewed live
/// on-device before it's wired into real screens.
class EchoMascotPreview extends StatelessWidget {
  const EchoMascotPreview({super.key});

  static const _states = [
    (EchoState.idle, 'Idle', 'A quiet presence, always nearby'),
    (EchoState.listening, 'Listening', 'Rings ripple inward as it listens'),
    (EchoState.thinking, 'Thinking', 'A gentle swirl while it processes'),
    (EchoState.speaking, 'Speaking', 'Rings ripple outward with your briefing'),
    (EchoState.sleeping, 'Sleeping', 'Resting, recharging in the background'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        elevation: 0,
        foregroundColor: colors.textPrimary,
        title: Text(
          'Echo mascot',
          style: GoogleFonts.oldStandardTt(
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          // Hero, on a dark ground to show the glow.
          Container(
            height: 240,
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              color: const Color(0xFF12180F),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Center(
              child: EchoMascot(state: EchoState.idle, size: 180),
            ),
          ),
          ..._states.map(
            (s) => Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  EchoMascot(state: s.$1, size: 96),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.$2,
                          style: GoogleFonts.oldStandardTt(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          s.$3,
                          style: GoogleFonts.nunito(
                            fontSize: 14,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
