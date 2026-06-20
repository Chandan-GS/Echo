/// Central location for all AI prompt engineering for the briefing feature.
/// Tweak [briefingSystemInstruction] and [buildUserMessage] here without
/// touching any business logic in the cubit.

// ── System instruction ────────────────────────────────────────────────────────
// Intentionally short — 1.5B models follow fewer, clearer instructions
// better than a long rule list. The example carries the stylistic weight.
const String briefingSystemInstruction =
    'You are Echo, an intelligent and witty AI personal assistant, '
    'similar to Jarvis from Iron Man. '
    'When given a list of the user\'s notifications, write a short, '
    'smooth, spoken morning briefing in flowing prose — no lists, '
    'no headers, no numbers, no sign-offs. '
    'Speak directly and personally. Use **double asterisks** around '
    'important names, times, and action items. '
    'Never repeat the same fact twice. '
    '\n\n'
    'Perfect example output:\n'
    'Good morning, sir. The overnight deployment came through cleanly — '
    'zero errors, systems are healthy. '
    '**Mike** wants to push your meeting to **3 PM** since he\'s running behind, '
    'and your **Daily Standup** is still on at **10 AM**. '
    '**John from Legal** is waiting on your liability cap confirmation before '
    'the contract goes out, and **Priya** has sent the Figma links for the '
    '**Q3 Design Assets** review. **Sarah** flags the **Q4 merger terms** '
    'need revision before **Friday**. Your **dentist appointment** is tomorrow '
    'at **4:30 PM**, the Swiggy delivery is on its way, and your mum wants '
    'to know if you\'re joining for Sunday dinner. A full day ahead, sir.';

// ── User message ──────────────────────────────────────────────────────────────
String buildUserMessage(String notificationContext) =>
    'Here are my notifications for today:\n\n$notificationContext\n\n'
    'Write my morning briefing.';

// ── Context formatter ─────────────────────────────────────────────────────────
/// Formats raw notification entries into natural-language sentences instead
/// of a numbered list. This prevents the model from mirroring a list structure
/// in its output (the #1 cause of numbered responses from small models).
String formatNotification({
  required String source,
  required String sender,
  required String content,
}) {
  return '$sender ($source): $content';
}

// ── TTS-safe plain text ───────────────────────────────────────────────────────
/// Strips all markdown and list formatting so TTS reads clean prose.
String stripForTts(String rawText) {
  return rawText
      .replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => m.group(1)!)
      .replaceAll(RegExp(r'^\d+[\.\)]\s+', multiLine: true), '')
      .replaceAll(RegExp(r'^[-*•]\s+', multiLine: true), '')
      .trim();
}

// ── Post-processing ───────────────────────────────────────────────────────────
/// Removes email sign-off artifacts that small models tend to produce.
String stripSignOff(String text) {
  final signOffPatterns = RegExp(
    r'^(best regards|regards|sincerely|yours truly|warm regards|'
    r'\[your name\]|\[name\]|thank you for|yours faithfully|echo)',
    caseSensitive: false,
  );
  final lines = text.split('\n');
  for (int i = 0; i < lines.length; i++) {
    if (signOffPatterns.hasMatch(lines[i].trim())) {
      return lines.sublist(0, i).join('\n').trim();
    }
  }
  return text.trim();
}

/// Removes duplicate sentences that small models tend to repeat.
/// Normalises each sentence, checks for near-identical content, and
/// drops any sentence whose key nouns already appeared in a prior sentence.
String deduplicateSentences(String text) {
  // Split on sentence boundaries
  final sentences = text.split(RegExp(r'(?<=[.!?])\s+'));
  final seen = <String>[];
  final output = <String>[];

  for (final sentence in sentences) {
    final normalised = sentence
        .toLowerCase()
        .replaceAll(RegExp(r'\*\*'), '')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .trim();

    if (normalised.isEmpty) continue;

    // Check if the core content of this sentence already appeared
    bool isDuplicate = false;
    for (final prior in seen) {
      // If 60%+ of the words in this sentence also appear in a prior sentence
      final words = normalised.split(' ').where((w) => w.length > 4).toSet();
      final priorWords = prior.split(' ').where((w) => w.length > 4).toSet();
      if (words.isEmpty) break;
      final overlap = words.intersection(priorWords).length / words.length;
      if (overlap >= 0.6) {
        isDuplicate = true;
        break;
      }
    }

    if (!isDuplicate) {
      seen.add(normalised);
      output.add(sentence.trim());
    }
  }

  return output.join(' ').trim();
}

/// Strips robotic filler sentences that 1.5B models generate.
String stripFillerCommentary(String text) {
  // Pattern to match whole sentences that are filler commentary
  final patterns = [
    // That's a great start / That's a relief / That's a good scheduling request / That's another useful detail
    RegExp(r"\bThat['’]s\s+(a|an|another|quite|very|some|your)?\s*(great|good|positive|scheduling|specific|useful|key|relief|start|detail|update|point|time|information|piece|important)\b[^.!?]*[.!?]", caseSensitive: false),
    RegExp(r"\bThat is\s+(a|an|another|quite|very|some|your)?\s*(great|good|positive|scheduling|specific|useful|key|relief|start|detail|update|point|time|information|piece|important)\b[^.!?]*[.!?]", caseSensitive: false),
    // Important to include / Important to note
    RegExp(r"\b(Important|Crucial|Useful|Good)\s+to\s+(include|note|know|keep in mind|remember|check)\b[^.!?]*[.!?]", caseSensitive: false),
    // This is important / This is a key point
    RegExp(r"\bThis is\s+(an?|another)?\s*(important|key|useful|great|good|relief|detail|update|point|time)\b[^.!?]*[.!?]", caseSensitive: false),
    // Worth noting / Worth keeping in mind
    RegExp(r"\b(Worth|Its worth|It['’]s worth)\s+(noting|keeping in mind|remembering)\b[^.!?]*[.!?]", caseSensitive: false),
  ];

  var cleaned = text;
  for (final pattern in patterns) {
    cleaned = cleaned.replaceAll(pattern, '');
  }

  // Also clean up trailing filler expressions within a sentence (e.g. ", which is a key point to note" or ", which is a relief")
  cleaned = cleaned.replaceAll(
    RegExp(r',\s*which is\s+(a|an|another|quite|very|some)?\s*(great|good|positive|scheduling|specific|useful|key|relief|start|detail|update|point|time|information|piece|important|worth noting)\b[^.!?]*', caseSensitive: false),
    '',
  );

  // Normalize spaces
  cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  return cleaned;
}

/// Fallback utility to wrap key names, times, and days of the week in double asterisks if the model missed them.
String autoBold(String text) {
  var result = text;

  // Auto-bold times: 10:00 AM, 3 PM, 4:30 PM
  final timeRegex = RegExp(r'\b\d{1,2}(?::\d{2})?\s*(?:AM|PM)\b', caseSensitive: false);
  result = _boldPatternIfNotBolded(result, timeRegex);

  // Auto-bold days of the week
  final dayRegex = RegExp(r'\b(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)\b', caseSensitive: false);
  result = _boldPatternIfNotBolded(result, dayRegex);

  // Auto-bold key names and specific terms
  final nameRegex = RegExp(r'\b(Mike|Priya|John|Sarah|Mom|Swiggy|DevOps Bot)\b');
  result = _boldPatternIfNotBolded(result, nameRegex);

  return result;
}

String _boldPatternIfNotBolded(String text, RegExp pattern) {
  return text.replaceAllMapped(pattern, (match) {
    final start = match.start;
    final end = match.end;

    // Check if the match is already surrounded by **
    bool isBoldedBefore = start >= 2 && text.substring(start - 2, start) == '**';
    bool isBoldedAfter = end <= text.length - 2 && text.substring(end, end + 2) == '**';

    if (isBoldedBefore && isBoldedAfter) {
      return match.group(0)!;
    } else {
      return '**${match.group(0)}**';
    }
  });
}

