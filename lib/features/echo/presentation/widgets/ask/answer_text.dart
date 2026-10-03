import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/data/ask/citations.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/ask_parts.dart';

/// Echo's answer as plain text on the page: **bold** details in green,
/// citations as small numbered dots, and each new word fading in as it
/// streams, the way Echo's speech bubble does.
class AnswerText extends StatefulWidget {
  final String text;

  /// How many sources there are; other numbers in brackets are left as text.
  final int sources;
  final void Function(int number)? onCite;

  const AnswerText(this.text, {super.key, required this.sources, this.onCite});

  @override
  State<AnswerText> createState() => _AnswerTextState();
}

class _AnswerTextState extends State<AnswerText>
    with SingleTickerProviderStateMixin {
  static const _fade = Duration(milliseconds: 250);

  final _clock = Stopwatch()..start();
  late final Ticker _ticker;
  var _pieces = <AnswerPiece>[];

  /// When each piece arrived, on [_clock].
  final _born = <Duration>[];

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      setState(() {});
      if (_born.isEmpty || _clock.elapsed - _born.last >= _fade) {
        _ticker.stop();
      }
    });
    // What's there when the answer first shows appears at once.
    _take(arrivedAt: _clock.elapsed - _fade);
  }

  @override
  void didUpdateWidget(covariant AnswerText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || old.sources != widget.sources) {
      _take(arrivedAt: _clock.elapsed);
      if (!_ticker.isActive) _ticker.start();
    }
  }

  void _take({required Duration arrivedAt}) {
    _pieces = answerPieces(_settled(widget.text), widget.sources);
    if (_born.length > _pieces.length) _born.length = _pieces.length;
    while (_born.length < _pieces.length) {
      _born.add(arrivedAt);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  double _opacity(int i) =>
      ((_clock.elapsed - _born[i]).inMilliseconds / _fade.inMilliseconds).clamp(
        0.0,
        1.0,
      );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i < _pieces.length; i++)
            switch (_pieces[i]) {
              WordPiece(:final text, :final bold) => TextSpan(
                text: text,
                style: TextStyle(
                  fontWeight: bold ? FontWeight.w800 : null,
                  color: (bold ? colors.primaryGreen : colors.textPrimary)
                      .withValues(alpha: _opacity(i)),
                ),
              ),
              CitePiece(:final numbers) => WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Opacity(
                  opacity: _opacity(i),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final n in numbers)
                        Padding(
                          padding: const EdgeInsets.only(left: 3),
                          child: CiteDot(
                            n,
                            onTap: widget.onCite == null
                                ? null
                                : () => widget.onCite!(n),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            },
        ],
      ),
      style: GoogleFonts.nunito(
        fontSize: 15.5,
        height: 1.55,
        color: colors.textPrimary,
      ),
    );
  }

  /// While streaming, a half-written citation ("[2") waits until it's
  /// complete.
  static String _settled(String text) =>
      withoutTodoTag(text).replaceFirst(RegExp(r'\s*\[[\d,\s]*$'), '');
}

sealed class AnswerPiece {}

/// A word with its following space, bold or not.
class WordPiece extends AnswerPiece {
  final String text;
  final bool bold;
  WordPiece(this.text, this.bold);
}

/// One citation mark: "[1, 3]".
class CitePiece extends AnswerPiece {
  final List<int> numbers;
  CitePiece(this.numbers);
}

/// [text] cut into words and citation marks; "**" toggles bold and isn't
/// shown. Bracketed numbers beyond [sources] stay as plain text.
List<AnswerPiece> answerPieces(String text, int sources) {
  final out = <AnswerPiece>[];
  var bold = false;
  void words(String s) {
    final parts = s.split('**');
    for (var p = 0; p < parts.length; p++) {
      if (p > 0) bold = !bold;
      for (final m in RegExp(r'\S+\s*|\s+').allMatches(parts[p])) {
        out.add(WordPiece(m[0]!, bold));
      }
    }
  }

  var at = 0;
  for (final m in citationPattern.allMatches(text)) {
    words(text.substring(at, m.start));
    final numbers = citedNumbers(m[0]!, sources);
    if (numbers.isEmpty) {
      words(m[0]!);
    } else {
      out.add(CitePiece(numbers));
    }
    at = m.end;
  }
  words(text.substring(at));
  return out;
}
