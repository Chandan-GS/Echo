import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/widgets/press_feedback.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/desktop/presentation/today/today_logic.dart';
import 'package:project_echo/features/desktop/presentation/today/today_parts.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/ask_parts.dart';
import 'package:project_echo/features/profile/data/week_stats.dart';

/// The right column: what's left of today, the briefing, and the week.
class TodayRail extends StatelessWidget {
  final List<RailEvent> events;
  final DateTime now;

  /// Today's briefing and when it was made; null text when there's none.
  final String? briefing;
  final DateTime? briefingAt;
  final bool playing;
  final VoidCallback onPlay;
  final WeekStats? week;

  const TodayRail({
    super.key,
    required this.events,
    required this.now,
    required this.briefing,
    required this.briefingAt,
    required this.playing,
    required this.onPlay,
    required this.week,
  });

  @override
  Widget build(BuildContext context) {
    final week = this.week;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      children: [
        const _Title('Rest of today'),
        _Timeline(events: events, now: now),
        const SizedBox(height: 18),
        _BriefingCard(
          text: briefing,
          madeAt: briefingAt,
          playing: playing,
          onPlay: onPlay,
        ),
        if (week != null) ...[
          const SizedBox(height: 18),
          const _Title('This week'),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Tile(
                  number: withCommas(week.todosDone),
                  label: 'to-dos done',
                  green: true,
                ),
                const SizedBox(width: 8),
                _Tile(
                  number: withCommas(week.replies),
                  label: 'replies via Echo',
                ),
                const SizedBox(width: 8),
                _Tile(number: withCommas(week.read), label: 'messages read'),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Title extends StatelessWidget {
  final String text;
  const _Title(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: GoogleFonts.oldStandardTt(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        color: context.colors.textPrimary,
      ),
    ),
  );
}

/// "Now", then each time still to come, down a thin line: to-dos with a
/// green ring, reminders with a grey one.
class _Timeline extends StatelessWidget {
  final List<RailEvent> events;
  final DateTime now;
  const _Timeline({required this.events, required this.now});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Stack(
      children: [
        Positioned(
          left: 6,
          top: 6,
          bottom: 6,
          child: Container(
            width: 2,
            decoration: BoxDecoration(
              color: c.dividerColor,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Stop(time: clockLabel(now), label: 'Now', now: true),
            for (final e in events) ...[
              const SizedBox(height: 12),
              _Stop(
                time: clockLabel(e.at),
                label: e.label,
                reminder: e.reminder,
              ),
            ],
            if (events.isEmpty) ...[
              const SizedBox(height: 12),
              _Stop(time: '', label: 'Nothing else with a time today'),
            ],
          ],
        ),
      ],
    );
  }
}

class _Stop extends StatelessWidget {
  final String time;
  final String label;
  final bool reminder;
  final bool now;
  const _Stop({
    required this.time,
    required this.label,
    this.reminder = false,
    this.now = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final green = c.primaryGreen;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 14,
          height: 14,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: now
                ? green
                : reminder
                ? c.background
                : c.surface,
            border: Border.all(
              color: reminder ? context.faint : green,
              width: 2.5,
            ),
            boxShadow: now
                ? [
                    BoxShadow(
                      color: green.withValues(alpha: 0.25),
                      spreadRadius: 4,
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (time.isNotEmpty)
                Text(
                  time,
                  style: GoogleFonts.nunito(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: reminder ? c.textSecondary : green,
                  ),
                ),
              Text(
                label,
                style: GoogleFonts.nunito(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                  color: c.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BriefingCard extends StatelessWidget {
  final String? text;
  final DateTime? madeAt;
  final bool playing;
  final VoidCallback onPlay;
  const _BriefingCard({
    required this.text,
    required this.madeAt,
    required this.playing,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = this.text;
    final at = madeAt;
    final note = text == null
        ? 'Your phone writes one each morning'
        : [
            if (at != null) 'Made at ${clockLabel(at)}',
            '${briefingMinutes(text)} min',
          ].join(' · ');
    return AskCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              Semantics(
                button: true,
                label: playing ? 'Stop the briefing' : 'Play the briefing',
                child: PressFeedback(
                  haptic: false,
                  scale: 0.92,
                  enabled: text != null,
                  child: Material(
                    color: text == null
                        ? c.textPrimary.withValues(alpha: 0.3)
                        : c.textPrimary,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: text == null ? null : onPlay,
                      child: SizedBox(
                        width: 42,
                        height: 42,
                        child: Icon(
                          playing
                              ? Symbols.stop_rounded
                              : Symbols.play_arrow_rounded,
                          size: 26,
                          fill: 1,
                          color: c.background,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text == null ? 'No briefing yet' : 'Today’s briefing',
                      style: GoogleFonts.nunito(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                    Text(
                      note,
                      style: GoogleFonts.nunito(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _Wave(playing: playing),
        ],
      ),
    );
  }
}

/// Bars that move while the briefing plays and lie flat when it doesn't.
class _Wave extends StatefulWidget {
  final bool playing;
  const _Wave({required this.playing});

  @override
  State<_Wave> createState() => _WaveState();
}

class _WaveState extends State<_Wave> with SingleTickerProviderStateMixin {
  static const _bars = 38;

  late final _ticker = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );

  @override
  void initState() {
    super.initState();
    if (widget.playing) _ticker.repeat();
  }

  @override
  void didUpdateWidget(_Wave old) {
    super.didUpdateWidget(old);
    if (widget.playing == old.playing) return;
    if (widget.playing) {
      _ticker.repeat();
    } else {
      _ticker
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = context.colors.primaryGreen.withValues(alpha: 0.55);
    return SizedBox(
      height: 22,
      child: AnimatedBuilder(
        animation: _ticker,
        builder: (context, _) {
          final t = _ticker.value * 2 * math.pi;
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < _bars; i++)
                Container(
                  width: 3,
                  height: widget.playing
                      ? 4 +
                            16 *
                                (math.sin(t * 3 + i * 0.7).abs() *
                                    (0.4 + 0.6 * math.sin(i * 1.7).abs()))
                      : 4,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final String number;
  final String label;
  final bool green;
  const _Tile({required this.number, required this.label, this.green = false});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: c.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              number,
              style: GoogleFonts.nunito(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: green ? c.primaryGreen : c.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              label,
              style: GoogleFonts.nunito(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                height: 1.25,
                color: c.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
