import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/services/reminders.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/data/home/home_feed.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/ask_parts.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/for_you_view.dart';
import 'package:project_echo/features/todo/data/todo_item.dart';
import 'package:project_echo/features/todo/data/todo_planner.dart';
import 'package:project_echo/features/todo/presentation/cubit/todo_cubit.dart';
import 'package:project_echo/features/todo/presentation/widgets/todo_card.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/widgets/press_feedback.dart';

/// Home's sections under the briefing. Each one is left out when it has
/// nothing to show, so a quiet day is a short Home.

/// "Needs you" in the masthead's serif, with a link or a note at the right.
class HomeSectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  final String? note;

  const HomeSectionHeader(
    this.title, {
    super.key,
    this.action,
    this.onAction,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 30, bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            title,
            style: GoogleFonts.oldStandardTt(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              height: 1.1,
              color: c.textPrimary,
            ),
          ),
          const Spacer(),
          if (action != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onAction,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  action!,
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: c.primaryGreen,
                  ),
                ),
              ),
            )
          else if (note != null)
            Text(
              note!,
              style: GoogleFonts.nunito(fontSize: 13, color: c.textSecondary),
            ),
        ],
      ),
    );
  }
}

/// The chats waiting on the owner, as Ask Echo's cards.
class NeedsYouSection extends StatelessWidget {
  final List<RawData> entries;
  final void Function(RawData) onReply;
  final void Function(RawData) onAdd;
  final VoidCallback onOpenAsk;

  const NeedsYouSection({
    super.key,
    required this.entries,
    required this.onReply,
    required this.onAdd,
    required this.onOpenAsk,
  });

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSectionHeader('Needs you', action: 'Ask Echo', onAction: onOpenAsk),
        for (final (i, e) in entries.take(HomeFeed.needsYouShown).indexed) ...[
          if (i > 0) const SizedBox(height: 10),
          ForYouCard(
            key: ValueKey(sourceKeyOf(e)),
            entry: e,
            onReply: onReply,
            onAdd: onAdd,
          ),
        ],
      ],
    );
  }
}

/// The next few things left today; ticking one lets the next slide up.
class UpNextSection extends StatelessWidget {
  final VoidCallback onSeeAll;
  const UpNextSection({super.key, required this.onSeeAll});

  static const shown = 3;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TodoCubit, TodoState>(
      builder: (context, todo) {
        final today = todo.today;
        if (!todo.hasList || today.isEmpty) return const SizedBox.shrink();
        final left = today.where((i) => !i.done).toList()
          ..sort((a, b) => a.sort.compareTo(b.sort));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HomeSectionHeader(
              'Up next',
              action: left.isEmpty
                  ? 'See today'
                  : 'All ${left.length} in To-do',
              onAction: onSeeAll,
            ),
            AskCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              child: AnimatedSize(
                duration: AppMotion.medium,
                curve: AppMotion.emphasized,
                alignment: Alignment.topCenter,
                child: Column(
                  children: left.isEmpty
                      ? [_AllDone(done: today.length)]
                      : [
                          for (final (i, item) in left.take(shown).indexed)
                            _UpNextRow(
                              key: ValueKey(item.id),
                              item: item,
                              first: i == 0,
                              onOpen: onSeeAll,
                            ),
                        ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AllDone extends StatelessWidget {
  final int done;
  const _AllDone({required this.done});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Icon(
            Symbols.check_circle_rounded,
            fill: 1,
            size: 22,
            color: c.primaryGreen,
          ),
          const SizedBox(width: 10),
          Text(
            done == 1 ? 'Done for today.' : 'All $done done for today.',
            style: GoogleFonts.nunito(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// A to-do as it reads in the list, whose circle ticks it off. The tick
/// shows for a moment before the row leaves.
class _UpNextRow extends StatefulWidget {
  final TodoItem item;
  final bool first;
  final VoidCallback onOpen;

  const _UpNextRow({
    super.key,
    required this.item,
    required this.first,
    required this.onOpen,
  });

  @override
  State<_UpNextRow> createState() => _UpNextRowState();
}

class _UpNextRowState extends State<_UpNextRow> {
  bool _ticked = false;

  Future<void> _tick() async {
    if (_ticked) return;
    setState(() => _ticked = true);
    await Future<void>.delayed(const Duration(milliseconds: 420));
    if (mounted) await toggleTodo(context, widget.item);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final item = widget.item;
    final from = [
      item.sender,
      item.app,
    ].where((s) => s.trim().isNotEmpty).join(', ');
    return AnimatedOpacity(
      duration: AppMotion.fast,
      opacity: _ticked ? 0.55 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: widget.first
              ? null
              : Border(
                  top: BorderSide(color: c.dividerColor.withValues(alpha: 0.6)),
                ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              button: true,
              label: 'Done',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _tick,
                child: AnimatedContainer(
                  duration: AppMotion.fast,
                  width: 26,
                  height: 26,
                  margin: const EdgeInsets.only(top: 1, right: 12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _ticked ? c.primaryGreen : Colors.transparent,
                    border: Border.all(
                      color: _ticked
                          ? c.primaryGreen
                          : c.primaryGreen.withValues(alpha: 0.55),
                      width: 2,
                    ),
                  ),
                  child: AnimatedScale(
                    duration: AppMotion.medium,
                    curve: AppMotion.spring,
                    scale: _ticked ? 1 : 0.4,
                    child: AnimatedOpacity(
                      duration: AppMotion.fast,
                      opacity: _ticked ? 1 : 0,
                      child: Icon(
                        Symbols.check_rounded,
                        size: 17,
                        color: context.isDarkMode
                            ? c.textInverse
                            : Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onOpen,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: GoogleFonts.nunito(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                        color: c.textPrimary,
                        decoration: _ticked ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: item.time ?? 'Anytime',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: c.primaryGreen,
                            ),
                          ),
                          if (from.isNotEmpty) TextSpan(text: ' · $from'),
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
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the owner told someone they'd do, with a time.
class PromisesSection extends StatelessWidget {
  final List<Promise> promises;
  final void Function(Promise) onAdd;
  final void Function(Promise) onDone;

  const PromisesSection({
    super.key,
    required this.promises,
    required this.onAdd,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    if (promises.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const HomeSectionHeader('You said you’d'),
        for (final (i, p) in promises.indexed) ...[
          if (i > 0) const SizedBox(height: 10),
          _PromiseCard(
            key: ValueKey(p.key),
            promise: p,
            onAdd: () => onAdd(p),
            onDone: () => onDone(p),
          ),
        ],
      ],
    );
  }
}

class _PromiseCard extends StatelessWidget {
  final Promise promise;
  final VoidCallback onAdd;
  final VoidCallback onDone;

  const _PromiseCard({
    super.key,
    required this.promise,
    required this.onAdd,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final entry = promise.entry;
    final remindAt = reminderTimeFor(entry, DateTime.now());
    return AskCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SourceBadge(promise.chat),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'You to '),
                      TextSpan(
                        text: promise.to,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                        ),
                      ),
                      TextSpan(text: ' · ${clockLabel(promise.turn.at)}'),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.nunito(
                    fontSize: 12.5,
                    color: c.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '“${promise.turn.text}”',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.nunito(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.35,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (remindAt != null)
                RemindPill(
                  entry: entry,
                  at: remindAt,
                  title: 'You told ${promise.to}',
                  filled: true,
                )
              else
                AskPill(
                  label: 'Add to my list',
                  icon: Symbols.checklist_rounded,
                  filled: true,
                  onTap: onAdd,
                ),
              AskPill(label: 'Did it', onTap: onDone),
            ],
          ),
        ],
      ),
    );
  }
}

/// Each busy group in one line, opening a catch-up in Ask Echo.
class BusyGroupsSection extends StatelessWidget {
  final List<BusyGroup> groups;

  /// Echo's line for each group, by name; its latest message otherwise.
  final Map<String, String> summaries;
  final void Function(String group) onCatchUp;

  const BusyGroupsSection({
    super.key,
    required this.groups,
    required this.onCatchUp,
    this.summaries = const {},
  });

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const HomeSectionHeader('Busy groups', note: 'not for you'),
        for (final (i, g) in groups.indexed) ...[
          if (i > 0) const SizedBox(height: 10),
          _GroupRow(
            group: g,
            summary: summaries[g.name],
            onTap: () => onCatchUp(g.name),
          ),
        ],
      ],
    );
  }
}

class _GroupRow extends StatelessWidget {
  final BusyGroup group;
  final String? summary;
  final VoidCallback onTap;
  const _GroupRow({
    required this.group,
    required this.summary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final latest = group.latest;
    final line =
        summary ??
        (latest.sender.isEmpty
            ? latest.content
            : '${latest.sender}: ${latest.content}');
    return PressFeedback(
      scale: 0.98,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: c.dividerColor.withValues(alpha: 0.6)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 10, 13),
            child: Row(
              children: [
                Icon(Symbols.forum_rounded, size: 20, color: c.textSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: group.name),
                            TextSpan(
                              text: ' · ${group.count} new',
                              style: TextStyle(
                                fontWeight: FontWeight.w400,
                                color: c.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.nunito(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // Echo's line can take two; a raw message, one.
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        layoutBuilder: (current, previous) => Stack(
                          alignment: Alignment.topLeft,
                          children: [...previous, ?current],
                        ),
                        child: Text(
                          line,
                          key: ValueKey(line),
                          maxLines: summary == null ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.nunito(
                            fontSize: 12.5,
                            height: 1.35,
                            color: c.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Symbols.chevron_right_rounded,
                  size: 22,
                  color: c.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
