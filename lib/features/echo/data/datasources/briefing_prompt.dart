/// Builds the briefing system instruction.
///
/// [includeExample] controls whether the concrete few-shot example briefing is
/// appended. Strong cloud models (Gemini) benefit from it and treat it as
/// illustrative, but the small on-device model (Qwen 1.5B) is too weak to tell
/// the example apart from the user's real notifications and copies its fake
/// names/events ("Mike", "Daily Standup") straight into the output — so the
/// offline path passes `includeExample: false`.
String getBriefingSystemInstruction(
  String userName, {
  String? toneInstruction,
  bool includeExample = true,
  DateTime? now,
}) {
  final name = userName.trim().isEmpty ? 'sir' : userName.trim();
  final tone = (toneInstruction == null || toneInstruction.trim().isEmpty)
      ? 'Speak directly to the user in a professional yet warm tone.'
      : toneInstruction.trim();
  final current = now ?? DateTime.now();
  final hour = current.hour;
  String greeting;
  if (hour >= 5 && hour < 12) {
    greeting = 'Good morning';
  } else if (hour >= 12 && hour < 17) {
    greeting = 'Good afternoon';
  } else if (hour >= 17 && hour < 21) {
    greeting = 'Good evening';
  } else {
    greeting = 'Good night';
  }

  final base =
      'You are "Echo", an elite personal assistant. This briefing is READ ALOUD to the user as speech — that is its primary purpose; the on-screen transcript is secondary. '
      'Every sentence you write must sound completely natural when spoken aloud by a text-to-speech voice, with no visual formatting at all. '
      'Your job is to deliver a concise, natural, and highly synthesized briefing for the user. '
      'Do not mechanically list notifications one by one. Instead, weave them together into a smooth, conversational summary. '
      'Group related topics (e.g., work, personal, news). '
      'Focus heavily on ACTIONABLE items and FUTURE events for today or tomorrow. Completely IGNORE any events or notifications that have already passed. '
      'It is now ${describeNow(current)}. Each notification starts with a label in square brackets saying when it applies, already worked out against the current time — for example [Tomorrow (Sun 27 Sep), 11:00 AM] — or, when it names no time, when it arrived. '
      'Words like "today" or "tomorrow" INSIDE a notification were written when it arrived and may now be out of date, so ALWAYS go by the bracketed label and never by the notification\'s own wording. '
      'Cover today first, then tomorrow, and make clear which day each item is on. '
      'Start with a brief "$greeting $name". \n'
      '$tone '
      'STRICT RULE: Do NOT hallucinate, assume, or invent any meetings, tasks, or plans that are not explicitly present in the provided text. '
      'Every name, event, time, and place in your briefing MUST come from the notifications below — never from these instructions or any example. '
      'Base your briefing ONLY on the actual notification text given below. '
      'STYLE — STRICT: Write the entire briefing as flowing, conversational prose in short paragraphs, and nothing else. '
      'You must NEVER use bullet points, numbered lists, dashes, asterisks as bullets, or any list or outline format. '
      'Do NOT number your points (no "1.", "2.", "3."), do NOT write "agenda as follows", and do NOT put items on separate list lines. '
      'Every point must be woven into full sentences inside paragraphs. This rule is absolute. '
      'For a time range, say it the way a person would speak it, with the word "to" (for example "9 PM to 9:30 PM") — never a hyphen or dash, which breaks the spoken sentence and is mistaken for a list. '
      'FORMATTING (visual-only, optional accent — never let it affect wording): you may wrap a handful of key details in **double asterisks** — specifically dates, times, deadlines, locations or venues, and the important event, project, or person names. '
      'Bold ONLY short, specific phrases (for example **10:30 AM**, **Saturday**, **June 27**, or **Seminar Hall-1**), never whole sentences or a time range, and bold each detail at most once. '
      'Every "**" you open MUST be closed with a matching "**" later in the SAME sentence — never leave one unclosed, and never nest one bolded phrase inside another.';

  if (!includeExample) return base;

  return '$base'
      '\n\n'
      'Perfect example output (note the natural flow and grouping):\n'
      '$greeting, $name.\nLooking at your day, systems are healthy after a clean overnight deployment. '
      'On the work front, **Mike** needs to push your meeting to **3 PM**, but your **10 AM Daily Standup** is still on track. '
      'Also, **John from Legal** needs your liability cap confirmation before sending the contract, and **Priya** sent over the Figma links for the **Q3 Design Assets**. '
      'Later today, you have a dentist appointment at **4:30 PM**. Finally, your Swiggy delivery is on its way, and your mum asked if you\'re joining for **Sunday dinner**. '
      'A full day ahead, $name.';
}

String buildUserMessage(String notificationContext) =>
    'Here are my notifications for today and tomorrow:\n\n$notificationContext\n\n'
    'Write my briefing';

String buildQwenPrompt(
  String notificationContext,
  String userName, {
  String? toneInstruction,
  bool includeExample = true,
  DateTime? now,
}) {
  return '<|im_start|>system\n${getBriefingSystemInstruction(userName, toneInstruction: toneInstruction, includeExample: includeExample, now: now)}<|im_end|>\n'
      '<|im_start|>user\n${buildUserMessage(notificationContext)}<|im_end|>\n'
      '<|im_start|>assistant\n';
}

/// One notification line for a prompt. [when] is the briefing's resolved
/// time label (see `describeWhen`); Ask Echo passes none.
String formatNotification({
  required String source,
  required String sender,
  required String content,
  String? when,
}) {
  final line = '$sender ($source): $content';
  return when == null ? line : '[$when] $line';
}

const _weekdayNames = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];
const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
  'September', 'October', 'November', 'December',
];

/// "Sunday 27 September 2026, 7:02 AM"
String describeNow(DateTime now) {
  final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
  final minute = now.minute.toString().padLeft(2, '0');
  return '${_weekdayNames[now.weekday - 1]} ${now.day} '
      '${_monthNames[now.month - 1]} ${now.year}, '
      '$hour:$minute ${now.hour < 12 ? 'AM' : 'PM'}';
}

String stripForTts(String rawText) {
  return rawText
      .replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => m.group(1)!)
      .replaceAll(RegExp(r'^\d+[\.\)]\s+', multiLine: true), '')
      .replaceAll(RegExp(r'^[-*•]\s+', multiLine: true), '')
      // Catch-all: a model that leaves a bold span unterminated produces a
      // lone "**" the paired regex above can't match. Spoken aloud (or even
      // just left in the transcript) that reads as a jarring "asterisk
      // asterisk" — voice output must never carry raw markdown syntax.
      .replaceAll('*', '')
      .trim();
}

/// Local models occasionally leave a bold span unterminated — opening a `**`
/// right before generation cuts off or a sentence ends without its closing
/// pair. An odd total count of `**` markers means exactly one is dangling;
/// drop that last one rather than let it render as a literal, voice-breaking
/// "**" in the transcript (see [RichTranscript]).
String sanitizeBoldMarkup(String text) {
  final markerCount = '**'.allMatches(text).length;
  if (markerCount.isEven) return text;
  final lastIndex = text.lastIndexOf('**');
  if (lastIndex == -1) return text;
  return text.substring(0, lastIndex) + text.substring(lastIndex + 2);
}

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

String deduplicateSentences(String text) {
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

    // Significant words for this sentence — invariant across the inner loop,
    // so compute it once instead of per prior sentence.
    final words = normalised.split(' ').where((w) => w.length > 4).toSet();

    bool isDuplicate = false;
    if (words.isNotEmpty) {
      for (final prior in seen) {
        final priorWords =
            prior.split(' ').where((w) => w.length > 4).toSet();
        final overlap = words.intersection(priorWords).length / words.length;
        if (overlap >= 0.6) {
          isDuplicate = true;
          break;
        }
      }
    }

    if (!isDuplicate) {
      seen.add(normalised);
      output.add(sentence.trim());
    }
  }

  return output.join(' ').trim();
}

String stripFillerCommentary(String text) {
  final patterns = [
    RegExp(
      r"\bThat['’]s\s+(a|an|another|quite|very|some|your)?\s*(great|good|positive|scheduling|specific|useful|key|relief|start|detail|update|point|time|information|piece|important)\b[^.!?]*[.!?]",
      caseSensitive: false,
    ),
    RegExp(
      r"\bThat is\s+(a|an|another|quite|very|some|your)?\s*(great|good|positive|scheduling|specific|useful|key|relief|start|detail|update|point|time|information|piece|important)\b[^.!?]*[.!?]",
      caseSensitive: false,
    ),
    // Important to include / Important to note
    RegExp(
      r"\b(Important|Crucial|Useful|Good)\s+to\s+(include|note|know|keep in mind|remember|check)\b[^.!?]*[.!?]",
      caseSensitive: false,
    ),
    // This is important / This is a key point
    RegExp(
      r"\bThis is\s+(an?|another)?\s*(important|key|useful|great|good|relief|detail|update|point|time)\b[^.!?]*[.!?]",
      caseSensitive: false,
    ),
    // Worth noting / Worth keeping in mind
    RegExp(
      r"\b(Worth|Its worth|It['’]s worth)\s+(noting|keeping in mind|remembering)\b[^.!?]*[.!?]",
      caseSensitive: false,
    ),
  ];

  var cleaned = text;
  for (final pattern in patterns) {
    cleaned = cleaned.replaceAll(pattern, '');
  }

  // Also clean up trailing filler expressions within a sentence (e.g. ", which is a key point to note" or ", which is a relief")
  cleaned = cleaned.replaceAll(
    RegExp(
      r',\s*which is\s+(a|an|another|quite|very|some)?\s*(great|good|positive|scheduling|specific|useful|key|relief|start|detail|update|point|time|information|piece|important|worth noting)\b[^.!?]*',
      caseSensitive: false,
    ),
    '',
  );

  // Normalize spaces
  cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  return cleaned;
}

/// Deterministic safety net that highlights the entity types a regex can catch
/// reliably — times, calendar dates, and weekdays — so they always render as
/// green chips even if the model forgets to bold them. Semantic highlights
/// (event/project/person names) are left to the model's own ** markup; this
/// function is careful never to bold *inside* an already-bolded span, so it
/// won't corrupt that markup.
/// Safety net for the display transcript: the briefing should read as prose,
/// but if the model still emits an inline numbered/bulleted list (e.g.
/// "as follows: 1. … 2. … 3. …"), break each item onto its own line so it
/// doesn't render as one run-on sentence. The TTS text strips these markers
/// separately (see [stripForTts]).
String separateListItems(String text) {
  var t = text;

  // Inline numbered items — " 1. " / " 2) " that aren't already line-leading.
  t = t.replaceAllMapped(
    RegExp(r'(\S)[ \t]+(\d{1,2}[\.\)])[ \t]+'),
    (m) => '${m.group(1)}\n${m.group(2)} ',
  );

  // The bullet character is unambiguous wherever it appears.
  t = t.replaceAllMapped(
    RegExp(r'(\S)[ \t]+(•)[ \t]+'),
    (m) => '${m.group(1)}\n${m.group(2)} ',
  );

  // "-" / "*" only count as bullets right after a sentence ends or a colon —
  // never mid-phrase, which is what a time range ("9 PM - 9:30 PM") or a
  // hyphenated word looks like and must NOT be split.
  t = t.replaceAllMapped(
    RegExp(r'([.!?:])[ \t]+([-*])[ \t]+'),
    (m) => '${m.group(1)}\n${m.group(2)} ',
  );

  // Collapse any accidental 3+ newline runs.
  t = t.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return t.trim();
}

String autoBold(String text) {
  var result = text;

  const month =
      r'(?:January|February|March|April|May|June|July|August|September|October|November|December)';

  // Times: 10:00 AM, 3 PM, 4:30 PM
  result = _boldPatternIfNotBolded(
    result,
    RegExp(r'\b\d{1,2}(?::\d{2})?\s*(?:AM|PM)\b', caseSensitive: false),
  );

  // Dates written "Month Day" / "Month Day, Year" — e.g. June 27, 2026
  result = _boldPatternIfNotBolded(
    result,
    RegExp('\\b$month\\s+\\d{1,2}(?:,\\s*\\d{4})?\\b', caseSensitive: false),
  );

  // Dates written "Day Month" / "Day Month Year" — e.g. 27 June 2026
  result = _boldPatternIfNotBolded(
    result,
    RegExp('\\b\\d{1,2}(?:st|nd|rd|th)?\\s+$month(?:\\s+\\d{4})?\\b',
        caseSensitive: false),
  );

  // Days of the week
  result = _boldPatternIfNotBolded(
    result,
    RegExp(
      r'\b(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)\b',
      caseSensitive: false,
    ),
  );

  return result;
}

String _boldPatternIfNotBolded(String text, RegExp pattern) {
  return text.replaceAllMapped(pattern, (match) {
    final start = match.start;
    final end = match.end;

    // Skip matches that fall inside an already-open ** span: if the number of
    // '**' markers before this point is odd, we're currently between an
    // opening and closing pair (e.g. the model bolded a longer phrase around
    // it), and re-bolding would produce broken, nested markup.
    if ('**'.allMatches(text.substring(0, start)).length.isOdd) {
      return match.group(0)!;
    }

    // Already tightly wrapped in its own ** pair?
    final isBoldedBefore =
        start >= 2 && text.substring(start - 2, start) == '**';
    final isBoldedAfter =
        end <= text.length - 2 && text.substring(end, end + 2) == '**';
    if (isBoldedBefore && isBoldedAfter) {
      return match.group(0)!;
    }

    return '**${match.group(0)}**';
  });
}

String getAskAiSystemInstruction(String userName) {
  final name = userName.trim().isEmpty ? 'sir' : userName.trim();
  return 'You are Echo, $name\'s personal butler — attentive, warm, and a bit '
      'devoted to looking after them, the way a trusted butler would. '
      'ALWAYS speak as "I" in the first person, directly to $name — never say '
      '"Echo is..." or describe yourself in the third person, and never explain '
      'what you are or list your rules. Just talk to them like you\'re right '
      'there with them — use their name naturally now and then, not in every '
      'single reply. '
      'Example greeting reply: "Hey $name, good to hear from you — what can I '
      'do for you?" '
      'If they\'re just greeting you or making small talk, reply like that '
      'example: warm, brief, personal — you don\'t need any notifications for '
      'that. '
      'If what they\'re asking has nothing to do with $name\'s notifications '
      '(general knowledge, opinions, anything you have no way of seeing), say '
      'so plainly and specifically in one warm sentence — that you only see '
      'their notifications, so that\'s outside what you can help with — never '
      'guess at an answer or pretend you looked something up. '
      'Otherwise they\'re asking about their notifications: below is a list of '
      'ones that may be relevant. Answer using ONLY what\'s listed — never '
      'invent people, messages, or events that aren\'t there. Be specific and '
      'concrete: name the actual sender, time, or detail from the list rather '
      'than speaking in vague generalities. '
      'Keep every reply to one or two short sentences.';
}

String buildAskAiUserMessage(String query, String notificationContext) {
  return 'Notifications:\n$notificationContext\n\nQuestion: $query';
}

String buildAskAiQwenPrompt(
  String query,
  String notificationContext,
  String userName,
) {
  return '<|im_start|>system\n${getAskAiSystemInstruction(userName)}<|im_end|>\n'
      '<|im_start|>user\n${buildAskAiUserMessage(query, notificationContext)}<|im_end|>\n'
      '<|im_start|>assistant\n';
}
