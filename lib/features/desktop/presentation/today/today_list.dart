import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/desktop/presentation/today/today_logic.dart';
import 'package:project_echo/features/desktop/presentation/today/today_parts.dart';
import 'package:project_echo/features/echo/data/context/addressed.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/ask_parts.dart';

/// The left column: everything that wants the owner today, grouped, one
/// row each. The selected row is shaded with a green bar; handled ones fade.
class TodayList extends StatefulWidget {
  final List<TriageItem> items;
  final String? selected;
  final Set<String> handled;

  /// Echo's line for each busy group, by name.
  final Map<String, String> summaries;
  final ValueChanged<TriageItem> onSelect;

  const TodayList({
    super.key,
    required this.items,
    required this.selected,
    required this.handled,
    required this.summaries,
    required this.onSelect,
  });

  @override
  State<TodayList> createState() => _TodayListState();
}

class _TodayListState extends State<TodayList> {
  final _keys = <String, GlobalKey>{};

  @override
  void didUpdateWidget(TodayList old) {
    super.didUpdateWidget(old);
    // J and K move the selection; keep it in view.
    if (widget.selected != old.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final row = _keys[widget.selected]?.currentContext;
        if (row == null || !row.mounted) return;
        // Each does nothing unless the row is past its edge.
        for (final policy in const [
          ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        ]) {
          Scrollable.ensureVisible(
            row,
            duration: AppMotion.fast,
            curve: AppMotion.standard,
            alignmentPolicy: policy,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) return const _Empty();
    final children = <Widget>[];
    String? heading;
    for (final item in items) {
      if (item.heading != heading) {
        heading = item.heading;
        final n = items.where((i) => i.heading == heading).length;
        children.add(
          PanelLabel(
            heading,
            trailing: '$n',
            padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
          ),
        );
      }
      children.add(
        _Row(
          key: _keys.putIfAbsent(item.id, GlobalKey.new),
          item: item,
          selected: item.id == widget.selected,
          handled: widget.handled.contains(item.id),
          summary: item.group == null
              ? null
              : widget.summaries[item.group!.name],
          onTap: () => widget.onSelect(item),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 20),
      children: children,
    );
  }
}

class _Row extends StatelessWidget {
  final TriageItem item;
  final bool selected;
  final bool handled;
  final String? summary;
  final VoidCallback onTap;

  const _Row({
    super.key,
    required this.item,
    required this.selected,
    required this.handled,
    required this.summary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = item.entry;
    final ink = selected ? context.onRowSelected : c.textPrimary;
    final muted = selected
        ? context.onRowSelected.withValues(alpha: 0.75)
        : c.textSecondary;
    final text = switch (item.kind) {
      TriageKind.group =>
        summary ?? (e.sender.isEmpty ? e.content : '${e.sender}: ${e.content}'),
      _ => e.content,
    };
    return AnimatedOpacity(
      opacity: handled ? 0.45 : 1,
      duration: AppMotion.medium,
      curve: AppMotion.standard,
      child: Material(
        color: selected ? context.rowSelected : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 11,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    item.kind == TriageKind.group
                        ? _GroupBadge(color: muted)
                        : SourceBadge(e, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: item.kind == TriageKind.promise
                                      ? 'You'
                                      : item.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: ink,
                                  ),
                                ),
                                TextSpan(text: ' · ${item.where}'),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.nunito(
                              fontSize: 13.5,
                              color: muted,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.nunito(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                              color: ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          clockLabel(e.timestamp),
                          style: GoogleFonts.nunito(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: muted,
                          ),
                        ),
                        const SizedBox(height: 6),
                        switch (item.kind) {
                          TriageKind.waiting => ForYouTag(
                            Addressed.parse(e.addressed) ?? Addressed.direct,
                          ),
                          TriageKind.promise => const QuietTag('your promise'),
                          TriageKind.group => const SizedBox.shrink(),
                        },
                      ],
                    ),
                  ],
                ),
              ),
              if (selected)
                Positioned(
                  left: 0,
                  top: 10,
                  bottom: 10,
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: c.primaryGreen,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A busy group's badge: it's many people, not one app's message.
class _GroupBadge extends StatelessWidget {
  final Color color;
  const _GroupBadge({required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: 28,
    height: 28,
    decoration: BoxDecoration(
      color: context.colors.background,
      shape: BoxShape.circle,
      border: Border.all(color: context.colors.dividerColor),
    ),
    child: Icon(Symbols.forum_rounded, size: 15, color: color),
  );
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
    child: Text(
      'Nothing is waiting on you right now. New messages for you show up '
      'here as your phone hears them.',
      style: GoogleFonts.nunito(
        fontSize: 14,
        height: 1.5,
        color: context.colors.textSecondary,
      ),
    ),
  );
}
