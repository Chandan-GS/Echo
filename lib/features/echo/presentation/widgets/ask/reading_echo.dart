import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/presentation/cubit/ask_ai_cubit.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_mascot.dart';

/// Echo reading: his eyes sweep across and down, line by line, as if he's
/// reading a page. [happy] swaps in his squint for the moment he has it.
class ReadingEcho extends StatefulWidget {
  final double size;
  final bool happy;
  const ReadingEcho({super.key, required this.size, this.happy = false});

  @override
  State<ReadingEcho> createState() => _ReadingEchoState();
}

class _ReadingEchoState extends State<ReadingEcho>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  var _look = Offset.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final look = readingGaze(elapsed);
      if (look != _look) setState(() => _look = look);
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => EchoMascot(
    state: widget.happy ? EchoState.happy : EchoState.idle,
    size: widget.size,
    showRings: false,
    glow: false,
    gazeReach: 1.6,
    lookAt: widget.happy ? null : _look,
  );
}

/// Where a reading eye is [t] into reading: left to right along a line in
/// 0.72 s, a quick sweep back, and down a line, three lines a page.
Offset readingGaze(Duration t) {
  const line = 900;
  final ms = t.inMilliseconds;
  final f = (ms % line) / line;
  final row = (ms ~/ line) % 3;
  double smooth(double x) => x * x * (3 - 2 * x);
  final x = f < 0.8
      ? -0.85 + 1.7 * smooth(f / 0.8)
      : 0.85 - 1.7 * smooth((f - 0.8) / 0.2);
  return Offset(x, 0.1 + row * 0.3);
}

/// Ask Echo while it works: Echo reading beside the green pill, which says
/// what it's doing ("Reading 63 messages…", then "4 look relevant…").
class WorkingRow extends StatelessWidget {
  final AskProgress? progress;
  final bool happy;
  const WorkingRow({super.key, this.progress, this.happy = false});

  static String label(AskProgress? p) {
    if (p == null) return 'Thinking…';
    final found = p.found;
    if (found == null) {
      return 'Reading ${p.reading} message${p.reading == 1 ? '' : 's'}…';
    }
    return found == 1 ? 'One looks relevant…' : '$found look relevant…';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ReadingEcho(size: 42, happy: happy),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
          decoration: BoxDecoration(
            color: context.selectionFill,
            borderRadius: BorderRadius.circular(
              18,
            ).copyWith(bottomLeft: const Radius.circular(6)),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(
              label(progress),
              key: ValueKey(label(progress)),
              style: GoogleFonts.nunito(
                fontSize: 13.5,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w700,
                color: context.onSelection,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
