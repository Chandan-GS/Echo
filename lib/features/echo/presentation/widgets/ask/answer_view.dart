import 'dart:async';

import 'package:flutter/material.dart';
import 'package:project_echo/core/services/voice/echo_voice.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/data/ask/citations.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/presentation/cubit/ask_ai_cubit.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/answer_text.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/ask_parts.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/reading_echo.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Echo's turn in the chat: reading while it works, then the answer. When the
/// first words arrive Echo squints happily for a moment before handing over.
class EchoTurn extends StatefulWidget {
  final ChatMessage message;
  final AskProgress? progress;
  final VoidCallback? onAdd;
  final void Function(RawData source)? onOpenSource;

  /// Echo has said something since: show the words, not the cards.
  final bool earlier;

  const EchoTurn({
    super.key,
    required this.message,
    this.progress,
    this.onAdd,
    this.onOpenSource,
    this.earlier = false,
  });

  @override
  State<EchoTurn> createState() => _EchoTurnState();
}

class _EchoTurnState extends State<EchoTurn> {
  static const _squint = Duration(milliseconds: 450);

  /// Whether the answer has started arriving but Echo is still squinting.
  var _handingOver = false;
  Timer? _handover;

  @override
  void didUpdateWidget(covariant EchoTurn old) {
    super.didUpdateWidget(old);
    if (old.message.text.isEmpty &&
        widget.message.text.isNotEmpty &&
        old.message.isGenerating) {
      _handingOver = true;
      _handover = Timer(_squint, () {
        if (mounted) setState(() => _handingOver = false);
      });
    }
  }

  @override
  void dispose() {
    _handover?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final working = m.isGenerating && m.text.isEmpty;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topLeft,
        children: [...previous, ?current],
      ),
      child: working || _handingOver
          ? Align(
              key: const ValueKey('working'),
              alignment: Alignment.centerLeft,
              child: WorkingRow(progress: widget.progress, happy: !working),
            )
          : AnswerView(
              key: const ValueKey('answer'),
              message: m,
              onAdd: widget.onAdd,
              onOpenSource: widget.onOpenSource,
              earlier: widget.earlier,
            ),
    );
  }
}

/// An answer: what Echo looked through, the answer itself with its sources,
/// and one next step.
class AnswerView extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onAdd;
  final void Function(RawData source)? onOpenSource;

  /// An answer Echo has moved on from: its words and what it used, without
  /// the source cards and buttons.
  final bool earlier;

  const AnswerView({
    super.key,
    required this.message,
    this.onAdd,
    this.onOpenSource,
    this.earlier = false,
  });

  @override
  Widget build(BuildContext context) {
    final sources = message.ragSources;
    final cited = message.cited;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (sources.isNotEmpty) ...[
          _CheckedLine(checked: message.checked, sources: sources),
          const SizedBox(height: 10),
        ],
        AnswerText(
          message.text,
          sources: sources.length,
          onCite: onOpenSource == null
              ? null
              : (n) => onOpenSource!(sources[n - 1]),
        ),
        if (cited.isNotEmpty && !earlier) ...[
          const SizedBox(height: 12),
          _SourceCards(
            numbered: [
              for (final n in citedNumbers(message.text, sources.length))
                (n, sources[n - 1]),
            ],
            onOpen: onOpenSource,
          ),
        ],
        if (!message.isGenerating && message.text.isNotEmpty && !earlier) ...[
          const SizedBox(height: 12),
          _Actions(message: message, onAdd: onAdd),
        ],
      ],
    );
  }
}

/// "Checked 63 messages · used 4", opening onto everything that was used.
class _CheckedLine extends StatefulWidget {
  final int checked;
  final List<RawData> sources;
  const _CheckedLine({required this.checked, required this.sources});

  @override
  State<_CheckedLine> createState() => _CheckedLineState();
}

class _CheckedLineState extends State<_CheckedLine> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = widget.checked > 0
        ? 'Checked ${widget.checked} messages · used ${widget.sources.length}'
        : '${widget.sources.length} notifications used';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(_open ? 16 : 24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Symbols.inventory_2_rounded,
                    size: 14,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: GoogleFonts.nunito(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: Icon(
                      Symbols.keyboard_arrow_down_rounded,
                      size: 16,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: !_open
                ? const SizedBox(height: 0)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < widget.sources.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CiteDot(i + 1),
                                const SizedBox(width: 8),
                                SourceBadge(widget.sources[i], size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      WhoLine(widget.sources[i]),
                                      const SizedBox(height: 2),
                                      Text(
                                        widget.sources[i].content,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.nunito(
                                          fontSize: 12,
                                          height: 1.4,
                                          color: colors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
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

/// The messages an answer cites, numbered as in the text; tapping one opens
/// its app.
class _SourceCards extends StatelessWidget {
  final List<(int, RawData)> numbered;
  final void Function(RawData source)? onOpen;
  const _SourceCards({required this.numbered, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: numbered.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final (n, e) = numbered[i];
          return Material(
            color: colors.surface,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onOpen == null ? null : () => onOpen!(e),
              child: Container(
                width: 210,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: colors.dividerColor.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CiteDot(n),
                        const SizedBox(width: 6),
                        SourceBadge(e, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: WhoLine(
                            e,
                            showChat: false,
                            trailing: clockLabel(e.timestamp),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      e.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.nunito(
                        fontSize: 12.5,
                        height: 1.35,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One next step, plus listen.
class _Actions extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onAdd;
  const _Actions({required this.message, this.onAdd});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spoken = plainAnswer(message.text);
    return Row(
      children: [
        if (onAdd != null)
          AskSolidButton(
            label: message.todos > 1
                ? 'Add these ${message.todos} to my list'
                : 'Add it to my list',
            icon: Symbols.checklist_rounded,
            onTap: onAdd,
          ),
        const Spacer(),
        ValueListenableBuilder<String?>(
          valueListenable: EchoVoice.instance.speaking,
          builder: (context, sentence, _) {
            final speakingThis = sentence != null && spoken.contains(sentence);
            return IconButton(
              tooltip: speakingThis ? 'Stop' : 'Listen',
              icon: Icon(
                speakingThis ? Symbols.stop_rounded : Symbols.volume_up_rounded,
                size: 21,
                color: colors.textSecondary,
              ),
              onPressed: () async {
                final voice = EchoVoice.instance;
                await voice.stop();
                if (!speakingThis) voice.sayAll(spoken);
              },
            );
          },
        ),
      ],
    );
  }
}
