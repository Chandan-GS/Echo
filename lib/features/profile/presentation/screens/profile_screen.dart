import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/presentation/widgets/press_feedback.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/profile/data/week_stats.dart';

/// The owner's name, which a tap on the pencil edits, and how long they've
/// had Echo.
class ProfileIdentity extends StatefulWidget {
  final String name;
  final DateTime? since;

  /// Null where the name can't be changed (the computer shows the phone's).
  final ValueChanged<String>? onRename;

  const ProfileIdentity({
    super.key,
    required this.name,
    required this.since,
    required this.onRename,
  });

  @override
  State<ProfileIdentity> createState() => _ProfileIdentityState();
}

class _ProfileIdentityState extends State<ProfileIdentity> {
  bool _editing = false;
  late final _controller = TextEditingController(text: widget.name);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing) _done();
    });
  }

  @override
  void didUpdateWidget(ProfileIdentity old) {
    super.didUpdateWidget(old);
    if (!_editing && old.name != widget.name) _controller.text = widget.name;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _edit() {
    setState(() => _editing = true);
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
    _focus.requestFocus();
  }

  void _done() {
    setState(() => _editing = false);
    widget.onRename?.call(_controller.text);
  }

  static String _date(DateTime d) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final since = widget.since;
    final nameStyle = GoogleFonts.oldStandardTt(
      fontSize: 30,
      fontWeight: FontWeight.w700,
      height: 1.1,
      color: c.textPrimary,
    );
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_editing)
                TextField(
                  controller: _controller,
                  focusNode: _focus,
                  maxLength: 24,
                  textCapitalization: TextCapitalization.words,
                  onSubmitted: (_) => _done(),
                  cursorColor: c.primaryGreen,
                  style: nameStyle,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    counterText: '',
                    filled: false,
                    border: UnderlineInputBorder(
                      borderSide: BorderSide(color: c.primaryGreen, width: 2),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: c.primaryGreen, width: 2),
                    ),
                  ),
                )
              else
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        widget.name.isEmpty ? 'You' : widget.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: nameStyle,
                      ),
                    ),
                    if (widget.onRename != null)
                      PressFeedback(
                        scale: 0.85,
                        child: IconButton(
                          tooltip: 'Edit your name',
                          onPressed: _edit,
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            Symbols.edit_rounded,
                            size: 18,
                            color: c.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              if (since != null) ...[
                const SizedBox(height: 2),
                Text(
                  'With Echo since ${_date(since)}',
                  style: GoogleFonts.nunito(
                    fontSize: 13.5,
                    color: c.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The last seven days: three numbers, and the messages Echo read each day.
class WeekInNumbers extends StatelessWidget {
  final WeekStats? week;
  const WeekInNumbers({super.key, required this.week});

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final w = week;
    final now = DateTime.now();
    final from = w?.from ?? now;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 30, bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'This week',
                style: GoogleFonts.oldStandardTt(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '${from.day} ${_months[from.month - 1]} – '
                '${now.day} ${_months[now.month - 1]}',
                style: GoogleFonts.nunito(fontSize: 13, color: c.textSecondary),
              ),
            ],
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _Tile(
                value: w?.todosDone,
                label: 'to-dos done',
                accent: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Tile(value: w?.replies, label: 'replies through Echo'),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Tile(value: w?.read, label: 'messages read for you'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        WeekBarChart(
          title: 'Messages Echo read',
          byDay: w?.readByDay ?? List.filled(7, 0),
          from: from,
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final int? value;
  final String label;
  final bool accent;
  const _Tile({required this.value, required this.label, this.accent = false});

  /// "1,284".
  static String _number(int n) =>
      n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 96,
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.dividerColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Counts up when the numbers arrive.
          TweenAnimationBuilder<double>(
            tween: Tween(end: (value ?? 0).toDouble()),
            duration: const Duration(milliseconds: 700),
            curve: AppMotion.emphasized,
            builder: (context, v, _) => Text(
              value == null ? '–' : _number(v.round()),
              style: GoogleFonts.nunito(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                height: 1.05,
                letterSpacing: -0.5,
                color: accent ? c.primaryGreen : c.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const Spacer(),
          Text(
            label,
            maxLines: 2,
            style: GoogleFonts.nunito(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.25,
              color: c.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// A bar a day, to scale, today's in green; the count over each bar.
class WeekBarChart extends StatelessWidget {
  final String title;
  final List<int> byDay;
  final DateTime from;
  const WeekBarChart({
    super.key,
    required this.title,
    required this.byDay,
    required this.from,
  });

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _barMax = 92.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final most = byDay.fold(0, (a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.dividerColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'a day',
                style: GoogleFonts.nunito(
                  fontSize: 12.5,
                  color: c.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // The bars have a fixed height, so their labels can't grow far.
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: SizedBox(
              height: _barMax + 52,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final (i, n) in byDay.indexed)
                    Expanded(
                      child: _Bar(
                        count: n,
                        height: most == 0 ? 0 : _barMax * n / most,
                        today: i == byDay.length - 1,
                        letter:
                            _letters[DateTime(
                                  from.year,
                                  from.month,
                                  from.day + i,
                                ).weekday -
                                1],
                        delay: Duration(milliseconds: 60 * i),
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

class _Bar extends StatelessWidget {
  final int count;
  final double height;
  final bool today;
  final String letter;
  final Duration delay;

  const _Bar({
    required this.count,
    required this.height,
    required this.today,
    required this.letter,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final small = GoogleFonts.nunito(
      fontSize: 10.5,
      fontWeight: FontWeight.w700,
      color: c.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(count == 0 ? '' : '$count', style: small),
        const SizedBox(height: 4),
        TweenAnimationBuilder<double>(
          tween: Tween(end: height),
          duration: AppMotion.slow + delay,
          curve: AppMotion.emphasized,
          builder: (context, h, _) => Container(
            width: 26,
            // A sliver even on a quiet day, so the week's shape reads.
            height: h.clamp(3, double.infinity),
            decoration: BoxDecoration(
              color: today
                  ? c.primaryGreen
                  : c.primaryGreen.withValues(
                      alpha: context.isDarkMode ? 0.28 : 0.22,
                    ),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          letter,
          style: small.copyWith(
            fontWeight: FontWeight.w800,
            color: today ? c.textPrimary : c.textSecondary,
          ),
        ),
      ],
    );
  }
}
