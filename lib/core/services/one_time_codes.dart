/// What a one-time code becomes before a prompt leaves the phone.
const oneTimeCodeMask = '[code hidden]';

/// Words that say a nearby number is a code. English, Hinglish and Hindi.
final _cue = RegExp(
  r"\botp\b|\b2fa\b|\bpasscode\b|\bone[\s-]?time\s+(?:code|password|pin)\b"
  r"|\b(?:verification|verify|security|login|log[\s-]?in|sign[\s-]?in|auth"
  r"|authentication|confirmation|access|activation)\s+(?:code|pin)\b"
  r"|\byour\s+(?:\w+\s+){0,3}(?:code|pin)\b"
  r"|\b(?:code|pin)\s*(?:is\b|hai\b|:|=)"
  r"|\bdo\s*n[o'’]?t\s+share\b|\bnever\s+share\b|\bshare\s+mat\b"
  r"|ओटीपी|सत्यापन|कोड",
  caseSensitive: false,
);

/// 482913, 482-913, 4 8 2 9 1 3, G-482913 or A1B2C3. Dates, clock times,
/// decimals and ten-digit phone numbers don't match.
final _code = RegExp(
  r"(?<![\w/₹$]|\d[.,-])"
  r"(?:[A-Z]{1,3}-\d{4,8}"
  r"|\d{3,4}[ -]\d{3,4}"
  r"|\d(?: \d){3,7}"
  r"|\d{4,8}"
  r"|(?=[A-Z0-9]*\d)(?=[A-Z0-9]*[A-Z])[A-Z0-9]{6,10})"
  r"(?![\w/]|[.,-]\d)",
);

final _moneyBefore = RegExp(
  r"(?:\brs\.?|\binr|₹|\$)\s*$",
  caseSensitive: false,
);

/// How far from a cue a code can sit. Bank texts put the card and the amount
/// between the word OTP and the number.
const _before = 60;
const _after = 100;

bool _isCode(String text, Match m, List<Match> cues) {
  final nearCue = cues.any(
    (c) => m.end > c.start - _before && m.start < c.end + _after,
  );
  if (!nearCue) return false;
  final lead = text.substring(m.start < 8 ? 0 : m.start - 8, m.start);
  return !_moneyBefore.hasMatch(lead);
}

/// [text] with anything that reads as a one-time code masked. Runs on every
/// prompt bound for Gemini. It goes by wording, so a bare number with nothing
/// around it saying it's a code stays as it is.
String withoutOneTimeCodes(String text) {
  final cues = _cue.allMatches(text).toList();
  if (cues.isEmpty) return text;
  return text.replaceAllMapped(
    _code,
    (m) => _isCode(text, m, cues) ? oneTimeCodeMask : m[0]!,
  );
}

/// Whether [text] carries a one-time code. WaitingIntent.kt holds the same
/// patterns.
bool hasOneTimeCode(String text) {
  final cues = _cue.allMatches(text).toList();
  return cues.isNotEmpty &&
      _code.allMatches(text).any((m) => _isCode(text, m, cues));
}
