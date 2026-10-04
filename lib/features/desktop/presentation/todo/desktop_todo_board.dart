import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/services/reminder_settings.dart';
import 'package:project_echo/core/services/reminders.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/desktop/data/desktop_actions.dart';
import 'package:project_echo/features/desktop/presentation/todo/board_bars.dart';
import 'package:project_echo/features/desktop/presentation/todo/board_card.dart';
import 'package:project_echo/features/desktop/presentation/todo/board_column.dart';
import 'package:project_echo/features/desktop/presentation/todo/board_logic.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/ask_parts.dart';
import 'package:project_echo/features/todo/data/todo_item.dart';
import 'package:project_echo/features/todo/presentation/cubit/todo_cubit.dart';
import 'package:project_echo/features/todo/presentation/widgets/reminder_sheet.dart';

/// The desktop's To-do: the phone's list as a board of Today, Tomorrow and
/// Later. Cards drag between days, Shift-click picks several to act on at
/// once, and everything is done through the phone (see DesktopActions).
///
/// Reach [DesktopTodoBoardState.focusAdd] through a GlobalKey for ⌘N.
class DesktopTodoBoard extends StatefulWidget {
  const DesktopTodoBoard({super.key});

  @override
  State<DesktopTodoBoard> createState() => DesktopTodoBoardState();
}

class DesktopTodoBoardState extends State<DesktopTodoBoard>
    implements CardHost {
  final _addText = TextEditingController();
  final _addFocus = FocusNode();

  /// Reminders still to come, by the source key of what they're about.
  Map<String, DateTime> _reminders = const {};

  /// Cards showing their message and actions.
  final Set<int> _open = {};

  /// Cards picked with Shift-click, for the bulk bar.
  final Set<int> _picked = {};

  /// What's on the board as last built, so the bulk bar acts on the picked
  /// items as they are now.
  List<TodoItem> _onBoard = const [];

  /// Puts the cursor in the add field (⌘N).
  void focusAdd() => _addFocus.requestFocus();

  @override
  void initState() {
    super.initState();
    _loadReminders();
    Reminders.changed.addListener(_loadReminders);
    // Settings → Reminders changes Echo's suggestions.
    ReminderSettings.lead.addListener(_settingsChanged);
    ReminderSettings.suggest.addListener(_settingsChanged);
  }

  @override
  void dispose() {
    Reminders.changed.removeListener(_loadReminders);
    ReminderSettings.lead.removeListener(_settingsChanged);
    ReminderSettings.suggest.removeListener(_settingsChanged);
    _addText.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  void _settingsChanged() => setState(() {});

  Future<void> _loadReminders() async {
    final all = await Reminders.all();
    if (mounted) setState(() => _reminders = all);
  }

  // ── CardHost ─────────────────────────────────────────────────────────────

  @override
  DateTime? reminderFor(TodoItem item) => _reminders[item.sourceKey];

  @override
  bool isPicked(TodoItem item) => _picked.contains(item.id);

  @override
  bool isOpen(TodoItem item) => _open.contains(item.id);

  @override
  void tap(TodoItem item) {
    setState(() {
      if (HardwareKeyboard.instance.isShiftPressed || _picked.isNotEmpty) {
        _picked.contains(item.id)
            ? _picked.remove(item.id)
            : _picked.add(item.id);
      } else {
        _open.contains(item.id) ? _open.remove(item.id) : _open.add(item.id);
      }
    });
  }

  @override
  void tick(TodoItem item) {
    setState(() => _open.remove(item.id));
    DesktopActions.tick(item, done: !item.done);
    if (!item.done) _toast('Done: ${item.title}');
  }

  @override
  Future<void> remind(TodoItem item) async {
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
        await DesktopActions.unremind(item.sourceKey);
        _toast('Reminder removed');
      case null:
        break;
    }
  }

  @override
  Future<void> accept(TodoItem item, DateTime at) async {
    await _remind(item, at);
    _toast(
      'I’ll remind you ${whenLabel(at, DateTime.now())}',
      action: 'Change',
      onAction: () => remind(item),
    );
  }

  @override
  Future<void> move(List<TodoItem> items, BoardColumn to) async {
    final now = DateTime.now();
    final moving = [
      for (final i in items)
        if (BoardColumn.of(i, now) != to) i,
    ];
    if (moving.isEmpty) return;
    setState(() {
      _picked.removeAll(items.map((i) => i.id));
      _open.removeAll(moving.map((i) => i.id));
    });
    for (final i in moving) {
      await DesktopActions.move(i, to.dayFrom(now));
    }
    final where = to.label.toLowerCase();
    _toast(
      moving.length == 1
          ? 'Moved to $where'
          : 'Moved ${moving.length} to $where',
    );
  }

  @override
  Future<void> delete(TodoItem item) async {
    setState(() {
      _open.remove(item.id);
      _picked.remove(item.id);
    });
    await DesktopActions.delete(item);
    _toast(
      'Deleted “${item.title}”',
      action: 'Undo',
      onAction: () => DesktopActions.restore(item),
    );
  }

  @override
  List<TodoItem> dragLoad(List<TodoItem> items) {
    // Dragging a picked card takes everything picked along with it.
    if (!items.any(isPicked)) return items;
    return {...items, ..._onBoard.where(isPicked)}.toList();
  }

  // ── Everything else ──────────────────────────────────────────────────────

  Future<void> _remind(TodoItem item, DateTime at) async {
    // A message's chat, so the reminder's "Open chat" goes straight there.
    // Without it (not mirrored yet) the reminder still goes off.
    final entry = await IsarDataSource.entryForKey(
      item.sourceKey,
    ).catchError((_) => null);
    await DesktopActions.remind(
      key: item.sourceKey,
      at: at,
      title: item.title,
      body: isTyped(item)
          ? 'On your list for ${item.time ?? 'today'}.'
          : '${item.sender}: “${item.sourceText}”',
      todoId: item.id,
      thread: entry?.thread,
    );
  }

  Future<void> _add(String text) async {
    _addText.clear();
    final item = await DesktopActions.add(text);
    final now = DateTime.now();
    final at = suggestedReminder(item, now);
    final where = switch (daysBetween(now, item.day)) {
      0 => 'today',
      1 => 'tomorrow',
      _ => dayLabel(item.day),
    };
    _toast(
      at == null
          ? 'Added to $where'
          : 'Added to $where. I’d remind you ${whenLabel(at, now)}.',
      action: at == null ? null : 'Remind me',
      onAction: at == null ? null : () => _remind(item, at),
    );
  }

  /// "Remind me for all with a time": Echo's suggestion, for everything
  /// still to do that has one and no reminder.
  Future<void> _remindAll() async {
    final offers = offersIn(_onBoard, _reminders, DateTime.now());
    if (offers.isEmpty) {
      _toast('Nothing left with a time to remind you about');
      return;
    }
    for (final (item, at) in offers) {
      await _remind(item, at);
    }
    _toast('Reminders set for everything with a time');
  }

  List<TodoItem> get _pickedNow => _onBoard.where(isPicked).toList();

  Future<void> _bulkTomorrow() => move(_pickedNow, BoardColumn.tomorrow);

  Future<void> _bulkRemind() async {
    final picked = _pickedNow;
    final offers = offersIn(picked, _reminders, DateTime.now());
    setState(_picked.clear);
    if (offers.isEmpty) {
      _toast(
        picked.length == 1
            ? 'It doesn’t name a time. Open it to pick one.'
            : 'None of them name a time. Open one to pick a time.',
      );
      return;
    }
    for (final (item, at) in offers) {
      await _remind(item, at);
    }
    _toast(
      offers.length == 1
          ? 'I’ll remind you ${whenLabel(offers.first.$2, DateTime.now())}'
          : 'I’ll remind you about ${offers.length} of them',
    );
  }

  Future<void> _bulkDone() async {
    final undone = _pickedNow.where((i) => !i.done).toList();
    setState(_picked.clear);
    for (final i in undone) {
      await DesktopActions.tick(i, done: true);
    }
    if (undone.isNotEmpty) _toast('${undone.length} done');
  }

  void _toast(String text, {String? action, VoidCallback? onAction}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          width: 480,
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
    return BlocBuilder<TodoCubit, TodoState>(
      builder: (context, s) {
        final now = DateTime.now();
        final columns = {
          for (final col in BoardColumn.values) col: itemsIn(col, s.items, now),
        };
        _onBoard = [for (final items in columns.values) ...items];
        final picked = _onBoard.where(isPicked).length;
        return Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(onRemindAll: _remindAll),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
                  child: AddBar(
                    controller: _addText,
                    focus: _addFocus,
                    onAdd: _add,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 16, 28, 22),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (n, col) in BoardColumn.values.indexed) ...[
                          if (n > 0) const SizedBox(width: 16),
                          Expanded(
                            child: BoardColumnView(
                              column: col,
                              items: columns[col]!,
                              now: now,
                              host: this,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 22,
              child: Center(
                child: BulkBar(
                  count: picked,
                  onTomorrow: _bulkTomorrow,
                  onRemind: _bulkRemind,
                  onDone: _bulkDone,
                  onClear: () => setState(_picked.clear),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// "To-do", how the board works, and the one button for all of it.
class _Header extends StatelessWidget {
  final VoidCallback onRemindAll;
  const _Header({required this.onRemindAll});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.dividerColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'To-do',
                  style: GoogleFonts.oldStandardTt(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    height: 1.05,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Drag a card to another day. Shift-click to pick several.',
                  style: GoogleFonts.nunito(
                    fontSize: 14.5,
                    color: c.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          AskPill(
            label: 'Remind me for all with a time',
            icon: Symbols.notifications_active_rounded,
            onTap: onRemindAll,
          ),
        ],
      ),
    );
  }
}
