import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/presentation/widgets/chip_label.dart';

/// Parses a markdown-style string where **word** denotes important terms.
/// Important terms are rendered as styled inline highlight chips.
/// Regular text is rendered with the standard body style.
class RichTranscript extends StatelessWidget {
  final String rawText;

  const RichTranscript({super.key, required this.rawText});

  @override
  Widget build(BuildContext context) {
    final spans = _parseSpans(rawText);
    return RichText(text: TextSpan(children: spans));
  }

  List<InlineSpan> _parseSpans(String text) {
    final List<InlineSpan> spans = [];
    // Regex to find **bold** segments
    final regex = RegExp(r'\*\*(.+?)\*\*');
    int cursor = 0;

    for (final match in regex.allMatches(text)) {
      // Text before the match
      if (match.start > cursor) {
        spans.add(
          TextSpan(
            text: text.substring(cursor, match.start),
            style: _bodyStyle,
          ),
        );
      }

      // The highlighted chip
      final word = match.group(1)!;
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: ChipLabel(
            isOutline: false,
            text: word,
            backgroundColor: AppTheme.lightGreenBackground,
            textColor: AppTheme.primaryGreen,
          ),
        ),
      );

      cursor = match.end;
    }

    // Remaining text after last match
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: _bodyStyle));
    }

    return spans;
  }

  static final TextStyle _bodyStyle = GoogleFonts.nunito(
    fontSize: 16,
    height: 1.8,
    color: AppTheme.textPrimary,
  );
}
