import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/presentation/animations/fade_slide_in.dart';
import 'package:project_echo/core/services/reminder_settings.dart';
import 'package:project_echo/core/services/reminders.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/relevance/temporal_relevance.dart';
import 'package:project_echo/features/echo/data/reply/reply_sender.dart';
import 'package:project_echo/features/echo/presentation/cubit/briefing_cubit.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/ask_parts.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/reading_echo.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_mascot.dart';
import 'package:project_echo/features/todo/data/todo_item.dart';
import 'package:project_echo/features/todo/presentation/cubit/todo_cubit.dart';
import 'package:project_echo/features/todo/presentation/widgets/reminder_sheet.dart';
import 'package:project_echo/features/todo/presentation/widgets/todo_card.dart';
import 'package:project_echo/features/todo/presentation/widgets/todo_parts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_echo/core/presentation/widgets/press_feedback.dart';

/// The phone's To-do tab: everything Echo has put on the owner's list, and
/// anything they add, each with a reminder they can set — or Echo's
/// suggestion for one, when it names a time.
class TodoScreen extends StatefulWidget {
  const TodoScreen({super.key});

  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends State<TodoScreen> {
  /// Reminders still to come, by the source key of what they're about.
  Map<String, DateTime> _reminders = const {};

  /// Rows showing their message and actions.
  final Set<int> _open = {};

  /// Rows just ticked: they stay, struck through, then fold away.
  final Set<int> _leaving = {};

  bool _doneOpen = false;

  /// "Not now" on Echo's offer to set reminders, for the rest of the day.
  bool _offerDismissed = true;

  /// Just accepted the offer: Echo says so for a moment.
  bool _offerAccepted = false;

  static const _offerKey = 'todo_reminder_offer_dismissed';

  @override
  void initState() {
    super.initState();
    _loadReminders();
    Reminders.changed.addListener(_loadReminders);
    // Settings → Reminders changes Echo's suggestions.
    ReminderSettings.lead.addListener(_settingsChanged);
    ReminderSettings.suggest.addListener(_settingsChanged);
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) {
        setState(
          () => _offerDismissed =
              prefs.getString(_offerKey) == dayKey(DateTime.now()),
        );
      }
    });
  }

  @override
  void dispose() {
    Reminders.changed.removeListener(_loadReminders);
    ReminderSettings.lead.removeListener(_settingsChanged);
    ReminderSettings.suggest.removeListener(_settingsChanged);
    super.dispose();
  }

  void _settingsChanged() => setState(() {});

  Future<void> _loadReminders() async {
    final all = await Reminders.all();
    if (mounted) setState(() => _reminders = all);
  }

  // ── Reminders ────────────────────────────────────────────────────────────

  Future<void> _remind(TodoItem item, DateTime at) async {
    // A message's chat, so the reminder's "Open chat" goes straight there.
    final entry = await IsarDataSource.entryForKey(item.sourceKey);
    await Reminders.set(
      message: item.sourceKey,
      at: at,
      title: item.title,
      body: _isTyped(item)
          ? 'On your list for ${item.time ?? 'today'}.'
          : '${item.sender}: “${item.sourceText}”',
      todoId: item.id,
      thread: entry?.thread,
    );
  }

  Future<void> _openSheet(TodoItem item) async {
    final choice = await showReminderSheet(
      context,
      item,
      current: _reminders[item.sourceKey],
    );
    switch (choice) {
      case RemindAt(:final at):
        await _remind(item, at);
        _toast('I’ll remind you ${whenLabel(at, DateTime.now())}');
      case RemoveReminder():
        await Reminders.cancel(item.sourceKey);
        _toast('Reminder removed');
      case null:
        break;
    }
  }

  Future<void> _acceptSuggestion(TodoItem item, DateTime at) async {
    HapticFeedback.lightImpact();
    await _remind(item, at);
    _toast(
      'I’ll remind you ${whenLabel(at, DateTime.now())}',
      action: 'Change',
      onAction: () => _openSheet(item),
    );
  }

  Future<void> _acceptAll(List<(TodoItem, DateTime)> offers) async {
    HapticFeedback.mediumImpact();
    for (final (item, at) in offers) {
      await _remind(item, at);
    }
    setState(() => _offerAccepted = true);
    await Future<void>.delayed(const Duration(milliseconds: 3200));
    if (mounted) setState(() => _offerAccepted = false);
  }

  Future<void> _dismissOffer() async {
    setState(() => _offerDismissed = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_offerKey, dayKey(DateTime.now()));
  }

  // ── The list ─────────────────────────────────────────────────────────────

  Future<void> _add(String text) async {
    final item = await context.read<TodoCubit>().addTyped(text);
    if (item == null || !mounted) return;
    final now = DateTime.now();
    final at = suggestedReminder(item, now);
    final days = item.day.difference(startOfDay(now)).inDays;
    final where = switch (days) {
      0 => 'today',
      1 => 'tomorrow',
      _ => _dayLabel(item.day),
    };
    _toast(
      at == null
          ? 'Added to $where'
          : 'Added to $where. I’d remind you ${whenLabel(at, now)}.',
      action: at == null ? null : 'Remind me',
      onAction: at == null ? null : () => _remind(item, at),
    );
  }

  void _tick(TodoItem item) {
    setState(() {
      // Unticking happens in place; ticking strikes it, then folds it away.
      item.done ? _leaving.remove(item.id) : _leaving.add(item.id);
      _open.remove(item.id);
    });
    toggleTodo(context, item);
  }

  Future<void> _move(TodoItem item) async {
    final now = DateTime.now();
    final toTomorrow = !item.day.isAfter(startOfDay(now));
    final day = startOfDay(now).add(Duration(days: toTomorrow ? 1 : 0));
    setState(() => _open.remove(item.id));
    await context.read<TodoCubit>().moveTo(item.id, day);
    _toast('Moved to ${toTomorrow ? 'tomorrow' : 'today'}');
  }

  Future<void> _delete(TodoItem item) async {
    final cubit = context.read<TodoCubit>();
    setState(() => _open.remove(item.id));
    final gone = await cubit.remove(item.id);
    if (gone == null) return;
    _toast(
      'Deleted “${gone.title}”',
      action: 'Undo',
      onAction: () => cubit.restore(gone),
    );
  }

  void _toast(String text, {String? action, VoidCallback? onAction}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          // Above the nav dock, which the tab's bottom padding clears.
          margin: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.paddingOf(context).bottom,
          ),
          content: Text(text),
          // Gone after a few seconds even with a button (Flutter keeps those).
          persist: false,
          action: action == null
              ? null
              : SnackBarAction(label: action, onPressed: onAction ?? () {}),
        ),
      );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasBriefing = context.select(
      (BriefingCubit b) =>
          b.state is BriefingCached || b.state is BriefingReady,
    );
    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        bottom: false,
        child: BlocBuilder<TodoCubit, TodoState>(
          builder: (context, s) {
            final now = s.now;
            final tomorrow = startOfDay(now).add(const Duration(days: 1));
            final later =
                s.items
                    .where((i) => i.day.isAfter(tomorrow) && !i.done)
                    .toList()
                  ..sort((a, b) {
                    final byDay = a.day.compareTo(b.day);
                    return byDay != 0 ? byDay : a.sort.compareTo(b.sort);
                  });
            final offers = [
              for (final i in [...s.today, ...s.tomorrow, ...later])
                if (!i.done && !_reminders.containsKey(i.sourceKey))
                  if (suggestedReminder(i, now) case final at?) (i, at),
            ];
            var n = 0;
            Widget enter(Widget child) =>
                FadeSlideIn(delay: AppMotion.staggerDelay(n++), child: child);
            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              // Clears the nav dock (MainScaffold sets the bottom padding).
              padding: EdgeInsets.fromLTRB(
                24,
                24,
                24,
                MediaQuery.paddingOf(context).bottom + 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  enter(
                    Text(
                      'To-do',
                      style: GoogleFonts.oldStandardTt(
                        fontSize: 40,
                        fontWeight: FontWeight.w700,
                        color: context.colors.textPrimary,
                        height: 1.15,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  enter(_AddField(onAdd: _add)),
                  AnimatedSize(
                    duration: AppMotion.medium,
                    curve: AppMotion.emphasized,
                    alignment: Alignment.topCenter,
                    child: _offerAccepted
                        ? const Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: _OfferCard.done(),
                          )
                        : offers.length > 1 && !_offerDismissed
                        ? Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: _OfferCard(
                              count: offers.length,
                              onAccept: () => _acceptAll(offers),
                              onDismiss: _dismissOffer,
                            ),
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                  ..._working(context, s, hasBriefing),
                  enter(_today(context, s)),
                  if (s.tomorrow.any((i) => !i.done))
                    enter(
                      _section(
                        context,
                        title: 'Tomorrow',
                        note: _dateLine(tomorrow),
                        items: s.tomorrow.where((i) => !i.done).toList(),
                        now: now,
                      ),
                    ),
                  if (later.isNotEmpty)
                    enter(
                      _section(
                        context,
                        title: 'Later',
                        note: 'This week and after',
                        items: later,
                        now: now,
                        showDay: true,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Making the list, updating it, or the way to make it.
  List<Widget> _working(BuildContext context, TodoState s, bool hasBriefing) {
    final c = context.colors;
    if (s.phase == TodoPhase.writing || s.phase == TodoPhase.updating) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Align(
            alignment: Alignment.centerLeft,
            child: WorkingRow(
              text: s.phase == TodoPhase.writing
                  ? 'Reading today’s briefing for things to do…'
                  : 'Checking ${s.pendingNew} new messages…',
            ),
          ),
        ),
      ];
    }
    if (!s.hasList) {
      return [
        const SizedBox(height: 14),
        AskCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasBriefing
                    ? 'Echo can turn today’s briefing into a list for today and tomorrow.'
                    : 'Make today’s briefing on Home, and Echo can turn it into a list. Or add things above.',
                style: GoogleFonts.nunito(
                  fontSize: 14.5,
                  height: 1.45,
                  color: c.textSecondary,
                ),
              ),
              if (hasBriefing) ...[
                const SizedBox(height: 14),
                AskSolidButton(
                  label: 'Make a to-do list',
                  icon: Symbols.checklist_rounded,
                  onTap: () => context.read<TodoCubit>().make(),
                ),
              ],
            ],
          ),
        ),
      ];
    }
    if (s.pendingNew > 0) {
      return [
        const SizedBox(height: 12),
        UpdateRow(
          count: s.pendingNew,
          since: s.meta.updatedAt ?? s.meta.madeAt,
          onUpdate: () => context.read<TodoCubit>().update(),
        ),
      ];
    }
    return const [];
  }

  Widget _today(BuildContext context, TodoState s) {
    final c = context.colors;
    final now = s.now;
    final today = s.today;
    final left = today.where((i) => !i.done || _leaving.contains(i.id)).toList()
      ..sort((a, b) => a.sort.compareTo(b.sort));
    final done = today.where((i) => i.done && !_leaving.contains(i.id)).toList()
      ..sort((a, b) => (b.doneAt ?? now).compareTo(a.doneAt ?? now));
    final undone = today.where((i) => !i.done).toList();
    final next = undone.where((i) => i.startsAt?.isAfter(now) ?? false).toList()
      ..sort((a, b) => a.sort.compareTo(b.sort));
    final line = today.isEmpty
        ? 'Nothing for today yet'
        : undone.isEmpty
        ? 'All ${today.length} done'
        : '${undone.length} left'
              '${next.isEmpty ? '' : ' · next at ${next.first.time!.split(' to ').first}'}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(
          context,
          title: 'Today',
          note: line,
          trailing: today.isEmpty
              ? null
              : ProgressRing(
                  done: today.length - undone.length,
                  total: today.length,
                ),
        ),
        if (left.isEmpty && done.isNotEmpty)
          AllDonePanel(count: today.length, lastDoneAt: s.lastDoneToday)
        else if (left.isNotEmpty)
          AskCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: AnimatedSize(
              duration: AppMotion.medium,
              curve: AppMotion.emphasized,
              alignment: Alignment.topCenter,
              child: _rows(context, left, now, justAdded: s.justAdded),
            ),
          )
        else
          Text(
            'Add something above, or ask Echo to make your list.',
            style: GoogleFonts.nunito(fontSize: 14, color: c.textSecondary),
          ),
        if (done.isNotEmpty) ...[
          const SizedBox(height: 10),
          _DoneRow(
            count: done.length,
            open: _doneOpen,
            onTap: () => setState(() => _doneOpen = !_doneOpen),
          ),
          Reveal(
            open: _doneOpen,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: AskCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 2,
                ),
                child: _rows(context, done, now),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _section(
    BuildContext context, {
    required String title,
    required String note,
    required List<TodoItem> items,
    required DateTime now,
    bool showDay = false,
  }) {
    items.sort((a, b) {
      final byDay = a.day.compareTo(b.day);
      return byDay != 0 ? byDay : a.sort.compareTo(b.sort);
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context, title: title, note: note, small: true),
        AskCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: AnimatedSize(
            duration: AppMotion.medium,
            curve: AppMotion.emphasized,
            alignment: Alignment.topCenter,
            child: _rows(context, items, now, showDay: showDay),
          ),
        ),
      ],
    );
  }

  /// [items] as rows; the parts of one long message (more than three asks,
  /// split by Echo) stay together under it.
  Widget _rows(
    BuildContext context,
    List<TodoItem> items,
    DateTime now, {
    bool showDay = false,
    Set<int> justAdded = const {},
  }) {
    String base(TodoItem i) => i.sourceKey.split('#').first;
    final counts = <String, int>{};
    for (final i in items) {
      counts[base(i)] = (counts[base(i)] ?? 0) + 1;
    }
    final children = <Widget>[];
    final grouped = <String>{};
    for (final i in items) {
      final key = base(i);
      if ((counts[key] ?? 0) > 1) {
        if (!grouped.add(key)) continue;
        final parts = items.where((p) => base(p) == key).toList();
        children.add(
          _Group(
            first: children.isEmpty,
            parts: parts,
            header: parts.first,
            showDay: showDay,
            children: [
              for (final p in parts) _row(context, p, now, part: true),
            ],
          ),
        );
      } else {
        Widget row = _row(
          context,
          i,
          now,
          first: children.isEmpty,
          showDay: showDay,
        );
        if (justAdded.contains(i.id)) {
          row = FadeSlideIn(
            key: ValueKey('added-${i.id}'),
            offsetY: 12,
            child: row,
          );
        }
        children.add(row);
      }
    }
    return Column(children: children);
  }

  Widget _row(
    BuildContext context,
    TodoItem item,
    DateTime now, {
    bool first = false,
    bool part = false,
    bool showDay = false,
  }) {
    final reminder = _reminders[item.sourceKey];
    final suggestion = reminder == null ? suggestedReminder(item, now) : null;
    return Leavable(
      key: ValueKey('todo-${item.id}'),
      leaving: _leaving.contains(item.id),
      onGone: () => setState(() => _leaving.remove(item.id)),
      child: TodoListRow(
        item: item,
        first: first,
        part: part,
        showDay: showDay,
        open: _open.contains(item.id),
        reminder: reminder,
        suggestion: suggestion,
        onTick: () => _tick(item),
        onToggleOpen: () => setState(() {
          _open.contains(item.id) ? _open.remove(item.id) : _open.add(item.id);
        }),
        onRemind: () => _openSheet(item),
        onAcceptSuggestion: suggestion == null
            ? null
            : () => _acceptSuggestion(item, suggestion),
        onMove: () => _move(item),
        onDelete: () => _delete(item),
      ),
    );
  }

  Widget _header(
    BuildContext context, {
    required String title,
    required String note,
    Widget? trailing,
    bool small = false,
  }) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.oldStandardTt(
                    fontSize: small ? 22 : 26,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                AnimatedSwitcher(
                  duration: AppMotion.fast,
                  child: Text(
                    note,
                    key: ValueKey(note),
                    style: GoogleFonts.nunito(
                      fontSize: 13.5,
                      color: c.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  static String _dateLine(DateTime d) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
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
    return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
  }
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool _isTyped(TodoItem item) => item.sourceKey.startsWith('you|');

/// The text field at the top: type a to-do, with its time if it has one.
class _AddField extends StatefulWidget {
  final Future<void> Function(String) onAdd;
  const _AddField({required this.onAdd});

  @override
  State<_AddField> createState() => _AddFieldState();
}

class _AddFieldState extends State<_AddField> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();
    _controller.clear();
    _focus.unfocus();
    await widget.onAdd(text);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final typed = _controller.text.trim().isNotEmpty;
    return Container(
      height: 58,
      padding: const EdgeInsets.only(left: 16, right: 7),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(29),
        border: Border.all(color: c.dividerColor.withValues(alpha: 0.5)),
        boxShadow: context.isDarkMode
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Row(
        children: [
          Icon(Symbols.add_rounded, size: 22, color: c.primaryGreen),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => _submit(),
              cursorColor: c.primaryGreen,
              style: GoogleFonts.nunito(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: 'Add a to-do… “call the plumber at 11 tomorrow”',
                hintMaxLines: 1,
                hintStyle: GoogleFonts.nunito(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: c.textSecondary.withValues(alpha: 0.7),
                ),
              ),
            ),
          ),
          AnimatedScale(
            duration: AppMotion.medium,
            curve: AppMotion.spring,
            scale: typed ? 1 : 0,
            child: PressFeedback(
              scale: 0.88,
              child: GestureDetector(
                onTap: _submit,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: c.primaryGreen,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Symbols.arrow_upward_rounded,
                    size: 20,
                    color: context.isDarkMode ? c.textInverse : Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Echo offering to remind the owner before everything with a time.
class _OfferCard extends StatelessWidget {
  final int count;
  final VoidCallback? onAccept;
  final VoidCallback? onDismiss;

  const _OfferCard({
    required this.count,
    required this.onAccept,
    required this.onDismiss,
  });

  /// After accepting: Echo, pleased, says it's done.
  const _OfferCard.done() : count = 0, onAccept = null, onDismiss = null;

  static const _words = [
    'no',
    'one',
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
    'ten',
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final done = onAccept == null;
    final n = count < _words.length ? _words[count] : '$count';
    final style = GoogleFonts.nunito(
      fontSize: 14.5,
      fontWeight: FontWeight.w600,
      height: 1.45,
      color: c.textPrimary,
    );
    return AskCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 34,
                height: 34,
                child: OverflowBox(
                  maxWidth: 56,
                  maxHeight: 56,
                  child: EchoMascot(
                    size: 56,
                    state: done ? EchoState.happy : EchoState.idle,
                    showRings: false,
                    glow: false,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: done
                    ? Text(
                        'Done. I’ll remind you before each of them. Tap any bell to change one.',
                        style: style,
                      )
                    : Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text:
                                  '${n[0].toUpperCase()}${n.substring(1)} of your to-dos name a time. '
                                  'Want me to remind you before each? I’ve marked my times with ',
                            ),
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Icon(
                                Symbols.auto_awesome_rounded,
                                size: 15,
                                fill: 1,
                                color: c.primaryGreen,
                              ),
                            ),
                            const TextSpan(text: '.'),
                          ],
                        ),
                        style: style,
                      ),
              ),
            ],
          ),
          if (!done) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AskPill(
                  label: count == 2
                      ? 'Remind me for both'
                      : 'Remind me for all $n',
                  icon: Symbols.notifications_active_rounded,
                  filled: true,
                  onTap: onAccept,
                ),
                AskPill(label: 'Not now', onTap: onDismiss),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// "3 done today ›", opening the ticked-off items.
class _DoneRow extends StatelessWidget {
  final int count;
  final bool open;
  final VoidCallback onTap;
  const _DoneRow({
    required this.count,
    required this.open,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PressFeedback(
      scale: 0.98,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: c.dividerColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                Icon(
                  Symbols.check_circle_rounded,
                  size: 20,
                  fill: 1,
                  color: c.primaryGreen,
                ),
                const SizedBox(width: 10),
                Text(
                  '$count done today',
                  style: GoogleFonts.nunito(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: c.textSecondary,
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: open ? 0.25 : 0,
                  duration: Reveal.duration,
                  curve: Reveal.curve,
                  child: Icon(
                    Symbols.chevron_right_rounded,
                    size: 22,
                    color: c.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The parts of one long message, under a line saying whose it was.
class _Group extends StatelessWidget {
  final bool first;
  final List<TodoItem> parts;
  final TodoItem header;
  final bool showDay;
  final List<Widget> children;

  const _Group({
    required this.first,
    required this.parts,
    required this.header,
    required this.showDay,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final done = parts.where((p) => p.done).length;
    final who = header.sender.isEmpty ? header.app : header.sender;
    return Container(
      decoration: BoxDecoration(
        border: first
            ? null
            : Border(
                top: BorderSide(color: c.dividerColor.withValues(alpha: 0.6)),
              ),
      ),
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  value: parts.isEmpty ? 0 : done / parts.length,
                  strokeWidth: 3,
                  strokeCap: StrokeCap.round,
                  color: c.primaryGreen,
                  backgroundColor: c.dividerColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${parts.length} things from $who',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                        ),
                      ),
                      if (showDay)
                        TextSpan(text: ' · ${_dayLabel(header.day)}'),
                    ],
                  ),
                  style: GoogleFonts.nunito(
                    fontSize: 14.5,
                    color: c.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          Container(
            margin: const EdgeInsets.only(left: 12, top: 6),
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: c.primaryGreen.withValues(alpha: 0.35),
                  width: 2,
                ),
              ),
            ),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

String _dayLabel(DateTime d) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
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
  return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
}

/// One to-do: the tick, the title, when and from whom, and its reminder at
/// the right — set (green bell), Echo's suggestion (dashed, tap to accept),
/// or none (a bell to set one). Tapping it shows the message it came from
/// and what can be done with it.
class TodoListRow extends StatefulWidget {
  final TodoItem item;
  final bool first;

  /// One part of a split message: no "from" line, smaller.
  final bool part;

  /// Say which day (for Later).
  final bool showDay;
  final bool open;
  final DateTime? reminder;
  final DateTime? suggestion;
  final VoidCallback onTick;
  final VoidCallback onToggleOpen;
  final VoidCallback onRemind;
  final VoidCallback? onAcceptSuggestion;
  final VoidCallback onMove;
  final VoidCallback onDelete;

  const TodoListRow({
    super.key,
    required this.item,
    required this.first,
    required this.part,
    required this.showDay,
    required this.open,
    required this.reminder,
    required this.suggestion,
    required this.onTick,
    required this.onToggleOpen,
    required this.onRemind,
    required this.onAcceptSuggestion,
    required this.onMove,
    required this.onDelete,
  });

  @override
  State<TodoListRow> createState() => _TodoListRowState();
}

class _TodoListRowState extends State<TodoListRow> {
  /// The message it came from, looked up the first time the row opens.
  Future<RawData?>? _entry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final item = widget.item;
    if (widget.open) _entry ??= IsarDataSource.entryForKey(item.sourceKey);
    final from = [
      item.sender,
      item.app,
    ].where((s) => s.trim().isNotEmpty).join(', ');
    final when = [
      if (widget.showDay && !widget.part) _dayLabel(item.day),
      item.time ?? (widget.part ? null : 'Anytime'),
    ].whereType<String>().join(', ');
    return Container(
      padding: EdgeInsets.symmetric(vertical: widget.part ? 9 : 12),
      decoration: BoxDecoration(
        border: widget.first || widget.part
            ? null
            : Border(
                top: BorderSide(color: c.dividerColor.withValues(alpha: 0.6)),
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TodoCheck(
                done: item.done,
                onTap: widget.onTick,
                label: item.title,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.part ? null : widget.onToggleOpen,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedOpacity(
                        opacity: item.done ? 0.5 : 1,
                        duration: AppMotion.fast,
                        child: Text(
                          item.title,
                          style: GoogleFonts.nunito(
                            fontSize: widget.part ? 14.5 : 15.5,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                            color: c.textPrimary,
                            decoration: item.done
                                ? TextDecoration.lineThrough
                                : null,
                            decorationColor: c.textPrimary,
                            decorationThickness: 2.4,
                          ),
                        ),
                      ),
                      if (!widget.part || when.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text.rich(
                          TextSpan(
                            children: [
                              if (when.isNotEmpty)
                                TextSpan(
                                  text: when,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: item.done
                                        ? c.textSecondary
                                        : c.primaryGreen,
                                  ),
                                ),
                              if (!widget.part && from.isNotEmpty)
                                TextSpan(text: ' · $from'),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.nunito(
                            fontSize: 12.5,
                            color: c.textSecondary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (!item.done) ...[
                const SizedBox(width: 8),
                _ReminderChip(
                  reminder: widget.reminder,
                  suggestion: widget.suggestion,
                  onSet: widget.onRemind,
                  onAccept: widget.onAcceptSuggestion,
                ),
              ],
            ],
          ),
          if (!widget.part) Reveal(open: widget.open, child: _details(context)),
        ],
      ),
    );
  }

  Widget _details(BuildContext context) {
    final c = context.colors;
    final item = widget.item;
    final today = !item.day.isAfter(startOfDay(DateTime.now()));
    return Padding(
      padding: const EdgeInsets.only(left: 38, top: 10),
      child: FutureBuilder<RawData?>(
        future: _entry,
        builder: (context, snap) {
          final entry = snap.data;
          final chat = entry?.thread != null;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_isTyped(item) && item.sourceText.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Color.lerp(c.background, c.surface, 0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${item.sender}: ',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: c.textPrimary,
                          ),
                        ),
                        TextSpan(text: '“${item.sourceText}”'),
                      ],
                    ),
                    style: GoogleFonts.nunito(
                      fontSize: 13.5,
                      height: 1.45,
                      color: c.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (chat) ...[
                    AskPill(
                      label: 'Reply',
                      icon: Symbols.reply_rounded,
                      filled: true,
                      onTap: () => context.push('/echo/chat', extra: entry),
                    ),
                    AskPill(
                      label: 'Open chat',
                      icon: Symbols.open_in_new_rounded,
                      onTap: () => ReplySender.open(entry!),
                    ),
                  ],
                  AskPill(
                    label: widget.reminder == null
                        ? 'Remind me'
                        : 'Change reminder',
                    icon: Symbols.alarm_rounded,
                    onTap: widget.onRemind,
                  ),
                  AskPill(
                    label: today ? 'Tomorrow' : 'Today',
                    icon: Symbols.event_rounded,
                    onTap: widget.onMove,
                  ),
                  AskPill(
                    label: 'Delete',
                    icon: Symbols.delete_rounded,
                    onTap: widget.onDelete,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A to-do's reminder, at the end of its row.
class _ReminderChip extends StatelessWidget {
  final DateTime? reminder;
  final DateTime? suggestion;
  final VoidCallback onSet;
  final VoidCallback? onAccept;

  const _ReminderChip({
    required this.reminder,
    required this.suggestion,
    required this.onSet,
    required this.onAccept,
  });

  /// "7:40 PM" today; "Sun 9:40 AM" on another day.
  static String _time(DateTime t) {
    final now = DateTime.now();
    final clock = clockLabel(t);
    if (_sameDay(t, now)) return clock;
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[t.weekday - 1]} $clock';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final set = reminder;
    final offer = suggestion;
    final Widget chip;
    if (set != null) {
      chip = _chip(
        context,
        key: 'set',
        icon: Symbols.notifications_active_rounded,
        fill: true,
        label: _time(set),
        background: context.selectionFill,
        foreground: context.onSelection,
        onTap: onSet,
        semantics: 'Reminder at ${_time(set)}. Change it',
      );
    } else if (offer != null) {
      chip = _chip(
        context,
        key: 'offer',
        icon: Symbols.auto_awesome_rounded,
        fill: true,
        label: _time(offer),
        foreground: c.primaryGreen,
        dashed: true,
        onTap: onAccept ?? onSet,
        semantics: 'Remind me at ${_time(offer)}',
      );
    } else {
      chip = Semantics(
        key: const ValueKey('none'),
        button: true,
        label: 'Add a reminder',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onSet,
          child: SizedBox(
            width: 34,
            height: 28,
            child: Icon(
              Symbols.notification_add_rounded,
              size: 20,
              color: c.textSecondary.withValues(alpha: 0.7),
            ),
          ),
        ),
      );
    }
    return AnimatedSwitcher(
      duration: AppMotion.medium,
      switchInCurve: AppMotion.spring,
      transitionBuilder: (child, a) => ScaleTransition(
        scale: Tween(begin: 0.7, end: 1.0).animate(a),
        child: FadeTransition(opacity: a, child: child),
      ),
      child: chip,
    );
  }

  Widget _chip(
    BuildContext context, {
    required String key,
    required IconData icon,
    required bool fill,
    required String label,
    required Color foreground,
    required VoidCallback onTap,
    required String semantics,
    Color? background,
    bool dashed = false,
  }) {
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 10, 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, fill: fill ? 1 : 0, color: foreground),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.nunito(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: foreground,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
    return PressFeedback(
      scale: 0.9,
      child: Semantics(
        key: ValueKey(key),
        button: true,
        label: semantics,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            height: 28,
            child: dashed
                ? CustomPaint(
                    painter: _DashedStadium(foreground.withValues(alpha: 0.6)),
                    child: Center(widthFactor: 1, child: content),
                  )
                : DecoratedBox(
                    decoration: BoxDecoration(
                      color: background,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Center(widthFactor: 1, child: content),
                  ),
          ),
        ),
      ),
    );
  }
}

/// A dashed stadium outline: Echo's suggestion, not yet set.
class _DashedStadium extends CustomPainter {
  final Color color;
  _DashedStadium(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    ).deflate(0.75);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final metric in (Path()..addRRect(r)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 7) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedStadium old) => old.color != color;
}
