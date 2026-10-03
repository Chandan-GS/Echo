import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/presentation/widgets/press_feedback.dart';
import 'package:project_echo/core/services/reminders.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/desktop/presentation/todo/board_logic.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/ask_parts.dart';
import 'package:project_echo/features/todo/data/todo_item.dart';
import 'package:project_echo/features/todo/presentation/widgets/todo_parts.dart';

/// What a card needs from the board it's on: each to-do's reminder, whether
/// it's picked or open, and what to do when it's used.
abstract interface class CardHost {
  DateTime? reminderFor(TodoItem item);
  bool isPicked(TodoItem item);
  bool isOpen(TodoItem item);

  /// A click: picks it with Shift (or while picking), otherwise opens it.
  void tap(TodoItem item);
  void tick(TodoItem item);

  /// Opens the reminder sheet.
  void remind(TodoItem item);
  void accept(TodoItem item, DateTime at);
  void move(List<TodoItem> items, BoardColumn to);
  void delete(TodoItem item);

  /// What dragging [items] carries: them, and everything picked with them.
  List<TodoItem> dragLoad(List<TodoItem> items);
}

/// One card on the board: a single to-do, or the parts of a message Echo
/// split, under "3 things from Priya". Drag it to another column.
class BoardCard extends StatelessWidget {
  final List<TodoItem> parts;
  final BoardColumn column;
  final CardHost host;

  const BoardCard({
    super.key,
    required this.parts,
    required this.column,
    required this.host,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final load = host.dragLoad(parts);
        return Draggable<List<TodoItem>>(
          data: load,
          feedback: SizedBox(
            width: box.maxWidth,
            child: Material(
              type: MaterialType.transparency,
              child: Opacity(
                opacity: 0.95,
                child: _Shell(
                  lifted: true,
                  count: load.length,
                  child: _content(dragging: true),
                ),
              ),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.4,
            child: _Shell(child: _content(dragging: true)),
          ),
          child: _Shell(
            picked: parts.length == 1 && host.isPicked(parts.first),
            child: _content(),
          ),
        );
      },
    );
  }

  Widget _content({bool dragging = false}) {
    if (parts.length == 1) {
      return _Row(
        item: parts.first,
        column: column,
        host: host,
        dragging: dragging,
      );
    }
    return _Group(parts: parts, column: column, host: host, dragging: dragging);
  }
}

/// The card's surface, with a shadow under the pointer and a green outline
/// when picked. [count] badges a drag carrying more than this card.
class _Shell extends StatefulWidget {
  final Widget child;
  final bool picked;
  final bool lifted;
  final int count;

  const _Shell({
    required this.child,
    this.picked = false,
    this.lifted = false,
    this.count = 1,
  });

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final raised = _hover || widget.lifted;
    final radius = BorderRadius.circular(14);
    final card = AnimatedContainer(
      duration: AppMotion.fast,
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: radius,
        border: Border.all(color: c.dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: widget.lifted
                  ? 0.18
                  : raised && !context.isDarkMode
                  ? 0.07
                  : 0,
            ),
            blurRadius: widget.lifted ? 28 : 16,
            offset: Offset(0, widget.lifted ? 12 : 6),
          ),
        ],
      ),
      foregroundDecoration: widget.picked
          ? BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: c.primaryGreen, width: 2),
            )
          : null,
      child: widget.child,
    );
    return MouseRegion(
      cursor: widget.lifted
          ? SystemMouseCursors.grabbing
          : SystemMouseCursors.grab,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: widget.count < 2
          ? card
          : Stack(
              clipBehavior: Clip.none,
              children: [
                card,
                Positioned(
                  top: -8,
                  right: -8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: c.primaryGreen,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${widget.count}',
                      style: GoogleFonts.nunito(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: context.isDarkMode
                            ? context.onSelection
                            : Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// The parts of one long message, under a line saying whose it was, like
/// the phone's list.
class _Group extends StatelessWidget {
  final List<TodoItem> parts;
  final BoardColumn column;
  final CardHost host;
  final bool dragging;

  const _Group({
    required this.parts,
    required this.column,
    required this.host,
    required this.dragging,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final header = parts.first;
    final who = header.sender.isEmpty ? header.app : header.sender;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            MiniRing(
              done: parts.where((p) => p.done).length,
              total: parts.length,
              size: 22,
            ),
            const SizedBox(width: 10),
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
                    if (column == BoardColumn.later)
                      TextSpan(
                        text: ' · ${shortDay(header.day, DateTime.now())}',
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.nunito(
                  fontSize: 13.5,
                  color: c.textSecondary,
                ),
              ),
            ),
          ],
        ),
        Container(
          margin: const EdgeInsets.only(left: 10, top: 8),
          padding: const EdgeInsets.only(left: 10),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: c.primaryGreen.withValues(alpha: 0.35),
                width: 2,
              ),
            ),
          ),
          child: Column(
            children: [
              for (final (n, p) in parts.indexed)
                Padding(
                  padding: EdgeInsets.only(top: n == 0 ? 0 : 6),
                  child: _Row(
                    item: p,
                    column: column,
                    host: host,
                    dragging: dragging,
                    part: true,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One to-do: the tick, the title, when and from whom, and its reminder at
/// the right. A click shows the message it came from and what can be done
/// with it.
class _Row extends StatelessWidget {
  final TodoItem item;
  final BoardColumn column;
  final CardHost host;
  final bool dragging;

  /// One part of a split message: no "from" line (the group says it), and
  /// its own outline when picked.
  final bool part;

  const _Row({
    required this.item,
    required this.column,
    required this.host,
    required this.dragging,
    this.part = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final from = [
      item.sender,
      item.app,
    ].where((s) => s.trim().isNotEmpty).join(', ');
    final when = [
      if (column == BoardColumn.later && !part)
        shortDay(item.day, DateTime.now()),
      item.time ?? (part ? null : 'Anytime'),
    ].whereType<String>().join(', ');
    final reminder = host.reminderFor(item);
    final suggestion = reminder == null
        ? suggestedReminder(item, DateTime.now())
        : null;
    final row = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => host.tap(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TodoCheck(
                done: item.done,
                onTap: () => host.tick(item),
                label: item.title,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedOpacity(
                      opacity: item.done ? 0.5 : 1,
                      duration: AppMotion.fast,
                      child: Text(
                        item.title,
                        style: GoogleFonts.nunito(
                          fontSize: part ? 14 : 14.5,
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
                    if (!part || when.isNotEmpty) ...[
                      const SizedBox(height: 3),
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
                            if (!part && from.isNotEmpty)
                              TextSpan(text: ' · $from'),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.nunito(
                          fontSize: 12,
                          color: c.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!item.done) ...[
                const SizedBox(width: 8),
                _ReminderChip(
                  reminder: reminder,
                  suggestion: suggestion,
                  onSet: () => host.remind(item),
                  onAccept: suggestion == null
                      ? null
                      : () => host.accept(item, suggestion),
                ),
              ],
            ],
          ),
          // A dragged copy shows the card as it was, closed.
          if (!dragging)
            Reveal(
              open: host.isOpen(item),
              child: _Details(item: item, column: column, host: host),
            ),
        ],
      ),
    );
    if (!part) return row;
    final picked = host.isPicked(item);
    return AnimatedContainer(
      duration: AppMotion.fast,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: picked
            ? context.selectionFill.withValues(alpha: 0.25)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: picked ? c.primaryGreen : Colors.transparent,
          width: 2,
        ),
      ),
      child: row,
    );
  }
}

/// An open card: the message it came from, then Remind me, Move and Delete.
class _Details extends StatelessWidget {
  final TodoItem item;
  final BoardColumn column;
  final CardHost host;

  const _Details({
    required this.item,
    required this.column,
    required this.host,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(left: 36, top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isTyped(item) && item.sourceText.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Color.lerp(c.background, c.surface, 0.2),
                borderRadius: BorderRadius.circular(12),
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
                  fontSize: 13,
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
              AskPill(
                label: host.reminderFor(item) == null
                    ? 'Remind me'
                    : 'Change reminder',
                icon: Symbols.alarm_rounded,
                onTap: () => host.remind(item),
              ),
              MenuAnchor(
                menuChildren: [
                  for (final to in BoardColumn.values)
                    if (to != column)
                      MenuItemButton(
                        onPressed: () => host.move([item], to),
                        child: Text(
                          to.label,
                          style: GoogleFonts.nunito(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                ],
                builder: (context, menu, _) => AskPill(
                  label: 'Move',
                  icon: Symbols.event_rounded,
                  onTap: () => menu.isOpen ? menu.close() : menu.open(),
                ),
              ),
              AskPill(
                label: 'Delete',
                icon: Symbols.delete_rounded,
                onTap: () => host.delete(item),
              ),
            ],
          ),
          const SizedBox(height: 2),
        ],
      ),
    );
  }
}

/// A to-do's reminder, at the end of its row, as on the phone: set (green,
/// filled bell), Echo's suggestion (dashed, click to accept), or none (a
/// muted bell to set one).
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
    if (daysBetween(now, t) == 0) return clock;
    return '${shortDay(t, now)} $clock';
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
        label: _time(set),
        background: context.selectionFill,
        foreground: context.onSelection,
        onTap: onSet,
        tip: 'Change the reminder',
      );
    } else if (offer != null) {
      chip = _chip(
        context,
        key: 'offer',
        icon: Symbols.auto_awesome_rounded,
        label: _time(offer),
        foreground: c.primaryGreen,
        dashed: true,
        onTap: onAccept ?? onSet,
        tip: 'Remind me at ${_time(offer)}',
      );
    } else {
      chip = Tooltip(
        key: const ValueKey('none'),
        message: 'Add a reminder',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onSet,
            child: SizedBox(
              width: 30,
              height: 26,
              child: Icon(
                Symbols.notification_add_rounded,
                size: 18,
                color: c.textSecondary.withValues(alpha: 0.7),
              ),
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
    required String label,
    required Color foreground,
    required VoidCallback onTap,
    required String tip,
    Color? background,
    bool dashed = false,
  }) {
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 8, 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, fill: 1, color: foreground),
          const SizedBox(width: 3),
          Text(
            label,
            style: GoogleFonts.nunito(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: foreground,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
    return Tooltip(
      key: ValueKey(key),
      message: tip,
      child: PressFeedback(
        scale: 0.9,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: SizedBox(
              height: 24,
              child: dashed
                  ? CustomPaint(
                      painter: _DashedStadium(
                        foreground.withValues(alpha: 0.6),
                      ),
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

/// How much of something is done, as a thin ring that fills as it goes.
class MiniRing extends StatelessWidget {
  final int done;
  final int total;
  final double size;

  const MiniRing({
    super.key,
    required this.done,
    required this.total,
    this.size = 26,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: total == 0 ? 0 : done / total),
      duration: const Duration(milliseconds: 600),
      curve: AppMotion.emphasized,
      builder: (context, value, _) => SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          value: value,
          strokeWidth: 3,
          strokeCap: StrokeCap.round,
          color: c.primaryGreen,
          backgroundColor: c.dividerColor,
        ),
      ),
    );
  }
}
