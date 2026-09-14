import 'dart:async';
import 'package:flutter/material.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_mascot.dart';

class GeneratingView extends StatefulWidget {
  final String partial;
  const GeneratingView({super.key, required this.partial});

  @override
  State<GeneratingView> createState() => _GeneratingViewState();
}

class _GeneratingViewState extends State<GeneratingView> {
  Timer? _stepTimer;
  int _currentStepIndex = 0;

  static const List<String> _reasoningSteps = [
    'Accessing secure local vault…',
    'Analyzing semantic priority contexts…',
    'Ranking notification signals…',
    'Synthesizing summary briefings…',
    'Polishing output commentary…',
  ];

  @override
  void initState() {
    super.initState();

    _stepTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (mounted) {
        setState(() {
          _currentStepIndex = (_currentStepIndex + 1) % _reasoningSteps.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _stepTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final statusText = widget.partial.isNotEmpty
        ? widget.partial
        : _reasoningSteps[_currentStepIndex];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Text(
              'Echo is\nthinking…',
              style: GoogleFonts.oldStandardTt(
                fontSize: 40,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
                height: 1.15,
                letterSpacing: -0.5,
              ),
            ),

            // Echo herself, thinking — the mascot in its orbital-swirl state.
            // Expanded + FittedBox keeps it centered and shrinks it gracefully
            // on short / landscape layouts.
            Expanded(
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: EchoMascot(
                    state: EchoState.thinking,
                    size: 210,
                  ),
                ),
              ),
            ),

            Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SizeTransition(
                    sizeFactor: anim,
                    axis: Axis.horizontal,
                    child: child,
                  ),
                ),
                child: _StatusPill(
                  key: ValueKey<String>(statusText),
                  text: statusText,
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

/// The status chip using the app's contrast-safe selection colours so it reads
/// well in both light and dark mode.
class _StatusPill extends StatelessWidget {
  final String text;
  const _StatusPill({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final onSel = context.onSelection;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: context.selectionFill,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: onSel, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 15,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w700,
                color: onSel,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

