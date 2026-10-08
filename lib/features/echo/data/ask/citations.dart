import 'package:project_echo/features/echo/data/models/raw_data.dart';

/// Answers point at the notifications they use with numbers in square
/// brackets, "[2]" or "[1, 3]", numbered as in the prompt.
final citationPattern = RegExp(r'\s*\[(\d{1,2}(?:\s*,\s*\d{1,2})*)\]');

/// The numbers [text] cites that exist among [count] sources, in order of
/// first mention.
List<int> citedNumbers(String text, int count) {
  final seen = <int>{};
  for (final m in citationPattern.allMatches(text)) {
    for (final part in m[1]!.split(',')) {
      final n = int.parse(part.trim());
      if (n >= 1 && n <= count) seen.add(n);
    }
  }
  return seen.toList();
}

/// The sources [text] cites, in order of first mention.
List<RawData> citedSources(String text, List<RawData> sources) => [
  for (final n in citedNumbers(text, sources.length)) sources[n - 1],
];

/// An answer that names things for the owner to do ends with "[todo:N]",
/// N being how many; the tag isn't shown or spoken.
final todoTag = RegExp(r'\s*\[todo:\s*(\d+)\]\s*$', caseSensitive: false);

/// How many things [text] says the owner has to do: 0 when it doesn't say.
int todoCount(String text) =>
    int.tryParse(todoTag.firstMatch(text)?[1] ?? '') ?? 0;

/// [text] as shown: without the to-do tag, or the start of one still
/// streaming in.
String withoutTodoTag(String text) => text
    .replaceFirst(todoTag, '')
    .replaceFirst(
      RegExp(r'\s*\[(t(o(d(o(:\s*\d*)?)?)?)?)?$', caseSensitive: false),
      '',
    );

/// [text] as it should be spoken or remembered: no citation marks, no
/// bold markers, no to-do tag.
String plainAnswer(String text) => withoutTodoTag(
  text,
).replaceAll(citationPattern, '').replaceAll('**', '').trim();
