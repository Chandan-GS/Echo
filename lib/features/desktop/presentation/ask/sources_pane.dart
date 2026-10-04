import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/data/ask/citations.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/presentation/cubit/ask_ai_cubit.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/ask_parts.dart';

/// The messages an answer cites, in full, beside the chat: numbered as in
/// the answer, with a reply and a way to open each. The one whose number
/// was last pointed at is lit and brought into view.
class SourcesPane extends StatefulWidget {
  /// The answer shown; null before Echo has answered anything.
  final ChatMessage? answer;

  /// What was asked, to say which answer these are for.
  final String? question;

  /// The citation number lit in the answer.
  final int? lit;

  final ValueChanged<int> onPick;
  final ValueChanged<RawData> onReply;
  final ValueChanged<RawData> onOpen;

  const SourcesPane({
    super.key,
    required this.answer,
    this.question,
    this.lit,
    required this.onPick,
    required this.onReply,
    required this.onOpen,
  });

  @override
  State<SourcesPane> createState() => _SourcesPaneState();
}

class _SourcesPaneState extends State<SourcesPane> {
  final _scroll = ScrollController();
  final _cards = <int, GlobalKey>{};

  @override
  void didUpdateWidget(covariant SourcesPane old) {
    super.didUpdateWidget(old);
    final lit = widget.lit;
    if (lit != null && lit != old.lit) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(lit));
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Scrolls just far enough to show source [n] whole, as a browser's
  /// "nearest" does; a card already in view stays put.
  void _reveal(int n) {
    final card = _cards[n]?.currentContext?.findRenderObject();
    if (card == null || !_scroll.hasClients) return;
    final viewport = RenderAbstractViewport.of(card);
    final position = _scroll.position;
    final top = viewport.getOffsetToReveal(card, 0).offset;
    final bottom = viewport.getOffsetToReveal(card, 1).offset;
    final target = position.pixels > top
        ? top
        : position.pixels < bottom
        ? bottom
        : null;
    if (target == null) return;
    _scroll.animateTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
      duration: AppMotion.medium,
      curve: AppMotion.emphasized,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final answer = widget.answer;
    final sources = answer?.ragSources ?? const <RawData>[];
    final numbers = answer == null
        ? const <int>[]
        : citedNumbers(answer.text, sources.length);
    final question = widget.question;

    return DecoratedBox(
      decoration: BoxDecoration(
        // A shade off the page, so the pane reads as set back from the chat.
        color: Color.lerp(colors.background, colors.surface, 0.4),
        border: Border(left: BorderSide(color: colors.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sources',
                  style: GoogleFonts.oldStandardTt(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                if (question != null && numbers.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'For “$question”',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.nunito(
                      fontSize: 12.5,
                      height: 1.4,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: numbers.isEmpty
                ? _Note(
                    answer == null || answer.isGenerating
                        ? 'Sources show here when Echo answers.'
                        : "This answer didn't use any of your messages.",
                  )
                : SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final n in numbers)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _SourceCard(
                              key: _cards.putIfAbsent(n, GlobalKey.new),
                              number: n,
                              entry: sources[n - 1],
                              lit: n == widget.lit,
                              onTap: () => widget.onPick(n),
                              onReply: () => widget.onReply(sources[n - 1]),
                              onOpen: () => widget.onOpen(sources[n - 1]),
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

/// One cited message: who, where and when, the whole message, and what can
/// be done with it.
class _SourceCard extends StatelessWidget {
  final int number;
  final RawData entry;
  final bool lit;
  final VoidCallback onTap;
  final VoidCallback onReply;
  final VoidCallback onOpen;

  const _SourceCard({
    super.key,
    required this.number,
    required this.entry,
    required this.lit,
    required this.onTap,
    required this.onReply,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.standard,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: lit ? colors.primaryGreen : colors.dividerColor,
            ),
            boxShadow: [
              BoxShadow(
                color: colors.primaryGreen.withValues(alpha: lit ? 0.2 : 0),
                spreadRadius: 3,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CiteDot(number),
                  const SizedBox(width: 8),
                  SourceBadge(entry, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: WhoLine(
                      entry,
                      trailing:
                          '${entry.source} · ${sentLabel(entry.timestamp, DateTime.now())}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                entry.content,
                style: GoogleFonts.nunito(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  height: 1.45,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AskPill(
                    label: 'Reply',
                    icon: Symbols.reply_rounded,
                    onTap: onReply,
                  ),
                  AskPill(
                    label: 'Open',
                    icon: Symbols.open_in_new_rounded,
                    onTap: onOpen,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the pane says when it has nothing to show.
class _Note extends StatelessWidget {
  final String text;
  const _Note(this.text);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Symbols.format_quote_rounded,
              size: 28,
              color: colors.textSecondary.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 13.5,
                height: 1.45,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// When a message came in, from [now]: "11:02 AM" today, "Yesterday 9:40
/// PM", "Mon 9:40 AM" within the week, "12 Oct" before that.
String sentLabel(DateTime t, DateTime now) {
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(t.year, t.month, t.day)).inDays;
  if (days <= 0) return clockLabel(t);
  if (days == 1) return 'Yesterday ${clockLabel(t)}';
  const week = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  if (days < 7) return '${week[t.weekday - 1]} ${clockLabel(t)}';
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
  return '${t.day} ${months[t.month - 1]}';
}
