import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/core/utils/time_utils.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_state.dart';

/// The next-briefing countdown as a slim strip, so the to-do list can sit
/// higher on the home screen. Same schedule logic as `NextBriefingTimer`.
class NextBriefingStrip extends StatefulWidget {
  const NextBriefingStrip({super.key});

  @override
  State<NextBriefingStrip> createState() => _NextBriefingStripState();
}

class _NextBriefingStripState extends State<NextBriefingStrip> {
  DateTime _now = DateTime.now();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  DateTime _next(List<String> times) {
    final instances = <DateTime>[];
    for (final day in [_now, _now.add(const Duration(days: 1))]) {
      for (final t in times) {
        final parsed = parseBriefingTime(t);
        if (parsed == null) continue;
        instances.add(
          DateTime(day.year, day.month, day.day, parsed.hour, parsed.minute),
        );
      }
    }
    if (instances.isEmpty) {
      instances.add(
        DateTime(_now.year, _now.month, _now.day + (_now.hour < 7 ? 0 : 1), 7),
      );
    }
    instances.sort();
    return instances.firstWhere(
      (d) => d.isAfter(_now),
      orElse: () => instances.last,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, settings) {
        final next = _next(
          settings.briefingTimes.isEmpty
              ? const ['07:00']
              : settings.briefingTimes,
        );
        final left = next.difference(_now);
        String two(int n) => n.toString().padLeft(2, '0');
        final countdown =
            '${two(left.inHours)}:${two(left.inMinutes % 60)}:${two(left.inSeconds % 60)}';
        final h = next.hour % 12 == 0 ? 12 : next.hour % 12;
        final at = '$h:${two(next.minute)} ${next.hour < 12 ? 'AM' : 'PM'}';

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: c.dividerColor.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              SizedBox(
                height: 22,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < 9; i++) ...[
                      if (i > 0) const SizedBox(width: 5),
                      Container(
                        width: i % 4 == 0 ? 3 : 2,
                        height: i % 4 == 0 ? 20 : 10,
                        decoration: BoxDecoration(
                          color: i % 4 == 0
                              ? c.primaryGreen
                              : c.textSecondary.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Next briefing in',
                      style: GoogleFonts.nunito(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: c.textSecondary,
                      ),
                    ),
                    Text(
                      countdown,
                      style: GoogleFonts.nunito(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                        letterSpacing: -0.3,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                at,
                style: GoogleFonts.nunito(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: c.primaryGreen,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
