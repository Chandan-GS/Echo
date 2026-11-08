import 'package:flutter/material.dart';
import 'package:project_echo/core/services/streak_service.dart';
import 'package:project_echo/features/echo/presentation/screens/streak_celebration_screen.dart';

/// The streak celebration, opened from the green hero on You: the same screen
/// that plays when a day first counts.
class StreakScreen extends StatefulWidget {
  const StreakScreen({super.key});

  @override
  State<StreakScreen> createState() => _StreakScreenState();
}

class _StreakScreenState extends State<StreakScreen> {
  late final Future<StreakInfo> _streak = StreakService().current();

  @override
  Widget build(BuildContext context) => FutureBuilder<StreakInfo>(
    future: _streak,
    builder: (context, snap) {
      final info = snap.data;
      // The celebration's own canvas, so nothing flashes while it loads.
      if (info == null) return const ColoredBox(color: Color(0xFF0D0D0D));
      return StreakCelebrationScreen(days: info.current < 1 ? 1 : info.current);
    },
  );
}
