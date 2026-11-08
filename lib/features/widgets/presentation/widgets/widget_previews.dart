import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/widgets/person_avatar.dart';
import 'package:project_echo/core/services/home_widgets_service.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_mascot.dart';

/// Flutter renderings of Echo's home-screen widgets, matching their Android
/// layouts (res/layout/widget_*.xml) and colours, fed with the same data the
/// widgets draw from (WidgetData.previewState).

class _WidgetColors {
  final Color bg, text, text2, green, stroke, track, divider;
  final List<Color> age;
  const _WidgetColors(
    this.bg,
    this.text,
    this.text2,
    this.green,
    this.stroke,
    this.track,
    this.divider,
    this.age,
  );

  static _WidgetColors of(BuildContext context) => context.isDarkMode
      ? const _WidgetColors(
          Color(0xFF262626),
          Color(0xFFEFEFEF),
          Color(0xFFA0A0A0),
          Color(0xFF6EBC76),
          Color(0x296EBC76),
          Color(0xFF3A3A3A),
          Color(0x26A0A0A0),
          [Color(0xFF6EBC76), Color(0xFFE6C77A), Color(0xFFE58C76)],
        )
      : const _WidgetColors(
          Color(0xFFF4F2EE),
          Color(0xFF1E1E1E),
          Color(0xFF5A5A5A),
          Color(0xFF49884F),
          Color(0x1A49884F),
          Color(0xFFDCDAD3),
          Color(0x1F5A5A5A),
          [Color(0xFF49884F), Color(0xFFC9962E), Color(0xFFC0503B)],
        );

  Color ageColor(int band) => age[band.clamp(0, 2)];
}

BoxDecoration _card(Color bg, Color stroke) => BoxDecoration(
  color: bg,
  borderRadius: BorderRadius.circular(24),
  border: Border.all(color: stroke),
  boxShadow: const [
    BoxShadow(color: Color(0x47000000), blurRadius: 28, offset: Offset(0, 10)),
  ],
);

/// Waiting on you (4 × 2).
class WaitingWidgetPreview extends StatelessWidget {
  final HomeWidgetsState? data;
  const WaitingWidgetPreview({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final c = _WidgetColors.of(context);
    final faces = data?.waiting ?? const <WidgetFace>[];
    final count = data?.waitingCount ?? 0;
    final known = data?.waitingKnown ?? false;
    final listening = data?.listening ?? false;
    return Container(
      width: 312,
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      decoration: _card(c.bg, c.stroke),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: EchoMascot(size: 24, showRings: false, glow: false),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Waiting on you',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.oldStandardTt(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: c.text,
                  ),
                ),
              ),
              Text(
                count > 0
                    ? '$count waiting'
                    : (listening && known ? 'All clear' : ''),
                style: GoogleFonts.nunito(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: c.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (faces.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  if (listening && known) ...[
                    _Dot(size: 22, color: c.green, done: true, tick: c.bg),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      !listening
                          ? "Let Echo read your notifications to see who's waiting."
                          : !known
                          ? 'Open Echo once and the people waiting on you will show here.'
                          : "Nobody's waiting. You've answered everyone.",
                      style: GoogleFonts.nunito(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: c.text2,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final f in faces)
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PersonAvatar(
                          name: f.name,
                          size: 52,
                          ring: (age: f.age, progress: f.progress),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          f.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.nunito(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: c.text,
                          ),
                        ),
                        Text(
                          f.since,
                          style: GoogleFonts.nunito(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: c.ageColor(f.age),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Next to-do (4 × 1).
class NextTodoWidgetPreview extends StatelessWidget {
  final HomeWidgetsState? data;
  const NextTodoWidgetPreview({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final c = _WidgetColors.of(context);
    final next = data?.next;
    final due = next?.due;
    final countdown = next?.countdown;
    final hasList = data?.hasList ?? false;
    final todos = data?.todosToday ?? 0;
    final tomorrowTitle = data?.tomorrowTitle;

    final String title;
    Widget? trailing;
    if (next != null) {
      title = next.title;
      trailing = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            due ?? 'Today',
            style: GoogleFonts.nunito(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: c.green,
            ),
          ),
          if (countdown != null)
            Text(
              countdown,
              style: GoogleFonts.nunito(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: c.text2,
              ),
            ),
        ],
      );
    } else if (todos == 0 && tomorrowTitle != null) {
      title = tomorrowTitle;
      trailing = Text(
        'Tomorrow',
        style: GoogleFonts.nunito(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: c.green,
        ),
      );
    } else if (!hasList) {
      title = "Make a list from today's briefing";
    } else if (todos == 0) {
      title = 'Nothing due today';
    } else {
      title = 'Nothing else due today';
      trailing = _Dot(size: 24, color: c.green, done: true, tick: c.bg);
    }

    return Container(
      width: 312,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: _card(c.bg, c.stroke),
      child: Row(
        children: [
          if (next != null) ...[
            _Dot(size: 24, color: c.green, done: false, tick: c.bg),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Next to-do',
                  style: GoogleFonts.nunito(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: c.text2,
                  ),
                ),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.nunito(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: c.text,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
        ],
      ),
    );
  }
}

/// Echo (1 × 1): just the pearl and the count, right on the wallpaper.
class OrbWidgetPreview extends StatelessWidget {
  final HomeWidgetsState? data;
  const OrbWidgetPreview({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final c = _WidgetColors.of(context);
    final count = data?.waitingCount ?? 0;
    final oldest = data?.waiting.isEmpty ?? true ? 0 : data!.waiting.first.age;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 86,
          height: 86,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
              ),
              const EchoMascot(size: 78, showRings: false, glow: false),
              if (count > 0)
                Positioned(
                  top: 4,
                  right: 2,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 26),
                    height: 26,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.bg,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: c.ageColor(oldest),
                        width: 2,
                      ),
                    ),
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: c.text,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Echo',
          style: GoogleFonts.nunito(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }
}

/// Today (4 × 2).
class TodayWidgetPreview extends StatelessWidget {
  final HomeWidgetsState? data;
  const TodayWidgetPreview({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final c = _WidgetColors.of(context);
    final waiting = data?.waitingCount ?? 0;
    final oldest = data?.oldestDays ?? 0;
    final due = data?.dueToday ?? 0;
    final todos = data?.todosToday ?? 0;
    final owes = data?.owesYou ?? 0;
    final streak = data?.streak ?? 0;
    final date = data?.date ?? '';
    final week = (data?.week.length == 7) ? data!.week : List.filled(7, 0);
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final ready = data?.ready ?? false;
    final showButton = ready || (data?.briefingOn ?? true);

    Widget line(String n, String words) => Text.rich(
      TextSpan(
        children: [
          if (n.isNotEmpty)
            TextSpan(
              text: n,
              style: TextStyle(fontWeight: FontWeight.w800, color: c.green),
            ),
          TextSpan(text: words),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.nunito(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: c.text,
        height: 1.5,
      ),
    );

    return Container(
      width: 312,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: _card(c.bg, c.stroke),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          'Today',
                          style: GoogleFonts.oldStandardTt(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: c.text,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            streak > 0 ? '$date · $streak-day streak' : date,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.nunito(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: c.text2,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    line(
                      waiting > 0 ? '$waiting' : '',
                      waiting > 0
                          ? ' waiting on you · ${oldest == 0 ? 'since today' : (oldest == 1 ? 'oldest yesterday' : 'oldest $oldest days')}'
                          : (data?.waitingKnown ?? false)
                          ? 'Nobody waiting on you'
                          : "Open Echo to see who's waiting",
                    ),
                    Text.rich(
                      TextSpan(
                        children: [
                          if (due > 0)
                            TextSpan(
                              text: '$due',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: c.green,
                              ),
                            ),
                          TextSpan(
                            text: due > 0
                                ? (due == 1
                                      ? ' to-do due today'
                                      : ' to-dos due today')
                                : (todos > 0
                                      ? 'All to-dos done'
                                      : 'No to-dos due today'),
                          ),
                          if (owes > 0) ...[
                            TextSpan(
                              text: ' · $owes',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: c.green,
                              ),
                            ),
                            TextSpan(
                              text: owes == 1 ? ' owes you' : ' owe you',
                            ),
                          ],
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c.text,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (showButton) ...[
                const SizedBox(width: 10),
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: ready ? c.green : c.track,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    ready ? Symbols.play_arrow_rounded : Symbols.schedule_rounded,
                    fill: ready ? 1 : 0,
                    color: ready ? Colors.white : c.green,
                    size: 24,
                  ),
                ),
              ],
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Divider(height: 1, color: c.divider),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        letters[i],
                        style: GoogleFonts.nunito(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: c.text2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: switch (week[i]) {
                            2 => c.green,
                            1 =>
                              context.isDarkMode
                                  ? const Color(0xFF4A2A24)
                                  : const Color(0xFFFBDCD4),
                            3 => Colors.transparent,
                            _ =>
                              context.isDarkMode
                                  ? const Color(0xFF3A3A3A)
                                  : const Color(0xFFEAE6DD),
                          },
                          border: week[i] == 3
                              ? Border.all(color: c.green, width: 2.4)
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final double size;
  final Color color;
  final bool done;
  final Color tick;
  const _Dot({
    required this.size,
    required this.color,
    required this.done,
    required this.tick,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: done ? color : Colors.transparent,
      border: done
          ? null
          : Border.all(color: color.withValues(alpha: 0.55), width: 2),
    ),
    child: done
        ? Icon(Symbols.check_rounded, size: size * 0.62, color: tick)
        : null,
  );
}
