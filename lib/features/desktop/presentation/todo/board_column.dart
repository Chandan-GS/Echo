import 'package:flutter/material.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/presentation/animations/fade_slide_in.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/desktop/presentation/todo/board_card.dart';
import 'package:project_echo/features/desktop/presentation/todo/board_logic.dart';
import 'package:project_echo/features/todo/data/todo_item.dart';

/// One day of the board ("Today · Saturday · 4 left") and its cards. Cards
/// dropped on it move to its day; it lights up green while one is over it.
class BoardColumnView extends StatelessWidget {
  final BoardColumn column;
  final List<TodoItem> items;
  final DateTime now;
  final CardHost host;

  const BoardColumnView({
    super.key,
    required this.column,
    required this.items,
    required this.now,
    required this.host,
  });

  /// Something in [load] isn't on this column's day yet.
  bool _wants(List<TodoItem> load) =>
      load.any((i) => BoardColumn.of(i, now) != column);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final recess = Color.lerp(c.background, c.surface, 0.35)!;
    final cards = cardsOf(items);
    return DragTarget<List<TodoItem>>(
      onWillAcceptWithDetails: (d) => _wants(d.data),
      onAcceptWithDetails: (d) => host.move(d.data, column),
      builder: (context, over, _) {
        final lit = over.isNotEmpty;
        return AnimatedContainer(
          duration: AppMotion.fast,
          decoration: BoxDecoration(
            color: lit
                ? Color.lerp(recess, context.selectionFill, 0.25)
                : recess,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: lit ? c.primaryGreen : c.dividerColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Heading(column: column, items: items, now: now),
              Expanded(
                child: cards.isEmpty
                    ? _Empty(column: column)
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                        itemCount: cards.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, n) {
                          final parts = cards[n];
                          // Keyed by what's on it, so a card keeps its
                          // place (and open state) as others come and go;
                          // one arriving from another column fades in.
                          return FadeSlideIn(
                            key: ValueKey(
                              'card-${parts.map((p) => p.id).join('-')}',
                            ),
                            offsetY: 8,
                            child: BoardCard(
                              parts: parts,
                              column: column,
                              host: host,
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Heading extends StatelessWidget {
  final BoardColumn column;
  final List<TodoItem> items;
  final DateTime now;

  const _Heading({
    required this.column,
    required this.items,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final note = columnNote(column, now, items);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 10),
      child: Row(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  column.label,
                  style: GoogleFonts.oldStandardTt(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: AnimatedSwitcher(
                    duration: AppMotion.fast,
                    child: Text(
                      note,
                      key: ValueKey(note),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.nunito(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: c.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (column == BoardColumn.today && items.isNotEmpty)
            MiniRing(
              done: items.where((i) => i.done).length,
              total: items.length,
            ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final BoardColumn column;
  const _Empty({required this.column});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Text(
        column == BoardColumn.today
            ? 'Nothing for today. Add something above, or drag a card here.'
            : 'Nothing yet. Drag a card here to move it.',
        textAlign: TextAlign.center,
        style: GoogleFonts.nunito(
          fontSize: 13,
          height: 1.45,
          color: context.colors.textSecondary,
        ),
      ),
    );
  }
}
