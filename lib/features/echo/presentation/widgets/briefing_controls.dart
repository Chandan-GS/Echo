import 'package:flutter/material.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/presentation/widgets/chip_label.dart';
import 'package:project_echo/core/presentation/widgets/echo_segmented.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';

/// The Morning / Evening switch at the top of the briefing.
class BriefingKindSwitch extends StatelessWidget {
  final bool evening;
  final ValueChanged<bool> onChanged;

  const BriefingKindSwitch({
    super.key,
    required this.evening,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Center(
      child: SizedBox(
        width: width < 300 ? width - 40 : 260,
        height: 46,
        child: EchoSegmented(
          labels: const ['Morning', 'Evening'],
          selected: evening ? 1 : 0,
          onSelect: (i) => onChanged(i == 1),
        ),
      ),
    );
  }
}

/// The transcript, with the sentence being read picked out and the ones
/// already read dimmed. [spoken] is what the voice is saying now.
class SpokenTranscript extends StatefulWidget {
  final String rawText;
  final String? spoken;

  const SpokenTranscript({super.key, required this.rawText, this.spoken});

  @override
  State<SpokenTranscript> createState() => _SpokenTranscriptState();
}

class _SpokenTranscriptState extends State<SpokenTranscript> {
  late List<String> _sentences = transcriptSentences(widget.rawText);

  /// The sentence being read; -1 while quiet.
  var _active = -1;

  @override
  void initState() {
    super.initState();
    _active = widget.spoken == null
        ? -1
        : matchSpokenSentence(_sentences, widget.spoken!, from: 0);
  }

  @override
  void didUpdateWidget(covariant SpokenTranscript old) {
    super.didUpdateWidget(old);
    if (old.rawText != widget.rawText) {
      _sentences = transcriptSentences(widget.rawText);
      _active = -1;
    }
    final spoken = widget.spoken;
    if (spoken == null) {
      _active = -1;
    } else if (spoken != old.spoken) {
      _active = matchSpokenSentence(
        _sentences,
        spoken,
        from: _active < 0 ? 0 : _active,
      );
    }
  }

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    key: ValueKey(_active),
    tween: Tween(begin: 0, end: 1),
    duration: AppMotion.medium,
    curve: AppMotion.standard,
    builder: (context, t, _) => Text.rich(
      TextSpan(
        children: [
          for (final (i, s) in _sentences.indexed)
            ..._spans(context, s, i < _active ? 1 : (i == _active ? 2 : 0), t),
        ],
      ),
    ),
  );

  /// [stage] 0 unread, 1 already read, 2 being read (fading in over [t]).
  List<InlineSpan> _spans(
    BuildContext context,
    String sentence,
    int stage,
    double t,
  ) {
    final c = context.colors;
    final base = GoogleFonts.nunito(
      fontSize: 16,
      height: 1.8,
      color: stage == 1 ? c.textSecondary : c.textPrimary,
    );
    final style = stage == 2
        ? base.copyWith(
            color: Color.lerp(c.textPrimary, context.onSelection, t),
            background: Paint()
              ..color = context.selectionFill.withValues(alpha: t),
          )
        : base;
    final bold = RegExp(r'\*\*(.+?)\*\*');
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final m in bold.allMatches(sentence)) {
      if (m.start > cursor) {
        spans.add(
          TextSpan(text: sentence.substring(cursor, m.start), style: style),
        );
      }
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: ChipLabel(
            isOutline: false,
            text: m.group(1)!,
            backgroundColor: c.lightGreenBackground,
            textColor: Colors.black,
          ),
        ),
      );
      cursor = m.end;
    }
    if (cursor < sentence.length) {
      spans.add(TextSpan(text: sentence.substring(cursor), style: style));
    }
    return spans;
  }
}

/// [text] cut into sentences the way the voice cuts them, keeping the space
/// and line breaks between them so they lay out as written.
List<String> transcriptSentences(String text) => [
  for (final m in RegExp(
    r'.+?(?:[.!?]+(?=\s|$)|$)',
    dotAll: true,
  ).allMatches(text))
    if (m[0]!.trim().isNotEmpty) m[0]!,
];

/// Which of [sentences] the voice is saying, from [from] on (it reads in
/// order), or [from] if none matches. Compared by letters and digits only,
/// since the spoken text has its markup stripped.
int matchSpokenSentence(
  List<String> sentences,
  String spoken, {
  required int from,
}) {
  String letters(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
  final said = letters(spoken);
  if (said.isEmpty) return from;
  for (var i = from.clamp(0, sentences.length); i < sentences.length; i++) {
    final s = letters(sentences[i]);
    if (s.isNotEmpty && (s.contains(said) || said.contains(s))) return i;
  }
  return from;
}
