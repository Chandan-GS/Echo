/// The second check on "Waiting on you": a message can be meant for the owner
/// and still ask nothing of them. Runs on the phone, on the text alone.
///
/// WaitingIntent.kt holds the same tables and the same order of checks, and
/// both sides run test/fixtures/wait_intent_vectors.tsv. Change them together.
library;

import 'package:project_echo/core/services/one_time_codes.dart';

enum WaitKind {
  question,
  request,
  call,
  invite,
  deadline,
  mention,
  ack,
  closer,
  emojiOnly,
  code,
  unsure,
}

/// Why a message is, or isn't, waiting on the owner.
class WaitReason {
  final WaitKind kind;
  final bool needsReply;

  /// "Asked you a question", for the card's chip.
  final String label;

  /// Each thing Echo noticed, for "Why?".
  final List<String> signals;

  const WaitReason({
    required this.kind,
    required this.needsReply,
    required this.label,
    this.signals = const [],
  });

  WaitReason copyWith({
    WaitKind? kind,
    bool? needsReply,
    String? label,
    List<String>? signals,
  }) => WaitReason(
    kind: kind ?? this.kind,
    needsReply: needsReply ?? this.needsReply,
    label: label ?? this.label,
    signals: signals ?? this.signals,
  );
}

// Every phrase is written the way waitTokens leaves text: lower case, straight
// apostrophes, words separated by one space.

const callPhrases = [
  'call me',
  'call back',
  'call when',
  'call asap',
  'call now',
  'call urgent',
  'please call',
  'give me a call',
  'give a call',
  'ring me',
  'phone me',
  'missed call',
  'missed voice call',
  'missed video call',
  'call karo',
  'call kar',
  'call kardo',
  'call karna',
  'phone karo',
  'phone kar',
  'phone kardo',
  'कॉल करो',
  'कॉल कर',
  'कॉल करना',
  'फोन करो',
  'फोन कर',
];

const callStarts = ['call', 'ring'];

const requestPhrases = [
  'can you',
  'could you',
  'would you',
  'will you',
  'can u',
  'could u',
  'would u',
  'will u',
  'please',
  'pls',
  'plz',
  'plss',
  'kindly',
  'let me know',
  'lmk',
  'need you to',
  'i need you',
  'want you to',
  'send me',
  'send it',
  'send the',
  'share the',
  'share it',
  'tell me',
  'give me',
  'help me',
  'remind me',
  'take a look',
  'have a look',
  'your thoughts',
  'thoughts on',
  'bhej dena',
  'bhej do',
  'bhej de',
  'bhejo',
  'bhejna',
  'bhejdo',
  'bhej dijiye',
  'kar do',
  'kar dena',
  'kar de',
  'kardo',
  'karde',
  'kar dijiye',
  'karo',
  'batana',
  'bata dena',
  'bata do',
  'bata de',
  'batao',
  'batado',
  'de do',
  'de dena',
  'dedo',
  'paise dena',
  'paise bhej',
  'paisa bhej',
  'dekh lena',
  'dekh lo',
  'dekho',
  'suno',
  'le aana',
  'le aao',
  'la dena',
  'भेज दो',
  'भेज देना',
  'भेजो',
  'भेजना',
  'कर दो',
  'कर देना',
  'करो',
  'बताओ',
  'बता दो',
  'बता देना',
  'बताना',
  'दे दो',
  'दे देना',
  'देख लो',
  'देखो',
  'सुनो',
];

const requestStarts = [
  'send',
  'share',
  'bring',
  'check',
  'review',
  'sign',
  'reply',
  'text',
  'tell',
  'give',
  'get',
  'pay',
  'book',
  'fix',
  'update',
  'forward',
  'confirm',
  'approve',
  'buy',
  'pick',
  'look',
  'remind',
  'ping',
  'drop',
];

const questionStarts = [
  'what',
  'when',
  'where',
  'who',
  'whom',
  'whose',
  'why',
  'how',
  'which',
  'did',
  'does',
  'do you',
  'do we',
  'are you',
  'are we',
  'is it',
  'is this',
  'is that',
  'was it',
  'were you',
  'will it',
  'should i',
  'should we',
  'shall we',
  'shall i',
  'can i',
  'can we',
  'could i',
  'could we',
  'have you',
  'has it',
  'any update',
  'any news',
  'kya',
  'kab',
  'kahan',
  'kaha',
  'kidhar',
  'kaise',
  'kaun',
  'kyun',
  'kyu',
  'kitna',
  'kitne',
  'kitni',
  'क्या',
  'कब',
  'कहाँ',
  'कैसे',
  'कौन',
  'क्यों',
  'कितना',
  'कितने',
  'कितनी',
];

const questionPhrases = [
  'how are you',
  'where are you',
  'what time',
  'what about you',
  'kya hua',
  'kya kar',
  'kaisa hai',
  'kaisi hai',
  'kaise ho',
  'kya haal',
  'hai kya',
  'ho kya',
  'kab tak',
  'है क्या',
];

const questionEnds = ['kya', 'क्या'];

const invitePhrases = [
  'you in',
  'join us',
  'join me',
  'come over',
  'come to',
  'are you free',
  'you free',
  'free tonight',
  'free today',
  'free tomorrow',
  'free this',
  'wanna come',
  'want to come',
  'wanna join',
  'want to join',
  'lets go',
  "let's go",
  'lets meet',
  "let's meet",
  'coming tonight',
  'coming today',
  'coming tomorrow',
  'party tonight',
  'dinner tonight',
  'dinner tomorrow',
  'chalo',
  'chalein',
  'chalega kya',
  'aaja',
  'aa ja',
  'aa jao',
  'aajao',
  'aa jana',
  'milte hain',
  'milna hai',
  'mil sakte',
  'चलो',
  'चलें',
  'आ जाओ',
  'आजा',
  'मिलते हैं',
];

const deadlinePhrases = [
  'by tomorrow',
  'by tonight',
  'by today',
  'by eod',
  'by eow',
  'by noon',
  'by morning',
  'by evening',
  'by monday',
  'by tuesday',
  'by wednesday',
  'by thursday',
  'by friday',
  'by saturday',
  'by sunday',
  'before tomorrow',
  'before tonight',
  'before eod',
  'before noon',
  'before monday',
  'before tuesday',
  'before wednesday',
  'before thursday',
  'before friday',
  'before saturday',
  'before sunday',
  'due today',
  'due tomorrow',
  'due tonight',
  'due by',
  'due on',
  'is due',
  'are due',
  'deadline',
  'asap',
  'urgent',
  'urgently',
  'jaldi',
  'kal tak',
  'aaj tak',
  'shaam tak',
  'subah tak',
  'raat tak',
  'कल तक',
  'आज तक',
  'जल्दी',
];

/// Words that look like an ask and aren't: "can you believe it", "yes please".
const notAskPhrases = [
  'can you believe',
  'could you believe',
  'would you believe',
  'yes please',
  'why not',
  'how sweet',
  'how nice',
  'how cute',
  'how cool',
  'how lovely',
  'how funny',
  'what a',
  'kya baat',
  'get well',
  'get some rest',
  'no need',
  'no worries',
  'koi nahi',
  'koi baat nahi',
  'nahi chahiye',
  'chalo theek',
  'chalo bye',
  'chal bye',
];

/// A message made only of these says nothing more than "ok".
const ackWords = [
  'thanks',
  'thank',
  'thanku',
  'thankyou',
  'thx',
  'ty',
  'tysm',
  'tq',
  'shukriya',
  'dhanyawad',
  'dhanyavaad',
  'appreciated',
  'appreciate',
  'it',
  'you',
  'so',
  'much',
  'very',
  'a',
  'lot',
  'ok',
  'okay',
  'okie',
  'okey',
  'oki',
  'okk',
  'okkk',
  'okkkk',
  'k',
  'kk',
  'kkk',
  'hmm',
  'hmmm',
  'hm',
  'mm',
  'mhm',
  'cool',
  'nice',
  'great',
  'awesome',
  'perfect',
  'super',
  'sure',
  'fine',
  'done',
  'yes',
  'yep',
  'yup',
  'yeah',
  'yea',
  'ya',
  'haan',
  'haa',
  'han',
  'ji',
  'noted',
  'got',
  'alright',
  'right',
  'understood',
  'roger',
  'ofc',
  'of',
  'course',
  'correct',
  'exactly',
  'true',
  'good',
  'and',
  'sir',
  'bro',
  'bhai',
  'dear',
  'mam',
  'धन्यवाद',
  'शुक्रिया',
  'ठीक',
  'है',
  'हाँ',
  'हां',
  'जी',
  'ओके',
];

const thankWords = [
  'thanks',
  'thank',
  'thanku',
  'thankyou',
  'thx',
  'ty',
  'tysm',
  'tq',
  'shukriya',
  'dhanyawad',
  'dhanyavaad',
  'appreciated',
  'धन्यवाद',
  'शुक्रिया',
];

const closerPhrases = [
  'see you',
  'see ya',
  'see u',
  'cya',
  'good night',
  'goodnight',
  'gn',
  'gm',
  'good morning',
  'bye',
  'byee',
  'byeee',
  'goodbye',
  'take care',
  'tc',
  'talk later',
  'talk soon',
  'ttyl',
  'no worries',
  'no problem',
  'np',
  'all good',
  'sounds good',
  'will do',
  'on my way',
  'omw',
  'reached',
  'haha',
  'hahaha',
  'hehe',
  'lol',
  'lmao',
  'rofl',
  'theek hai',
  'thik hai',
  'thikh hai',
  'tik hai',
  'accha',
  'achha',
  'acha',
  'koi nahi',
  'koi baat nahi',
  'ho gaya',
  'ho gya',
  'mil gaya',
  'mil gya',
  'kar diya',
  'bhej diya',
  'शुभ रात्रि',
  'ठीक है',
  'अच्छा',
  'हो गया',
  'मिल गया',
];

const stickerWords = ['sticker', 'gif'];

/// Every table, by the name it has in WaitingIntent.kt.
const waitPhraseTables = <String, List<String>>{
  'callPhrases': callPhrases,
  'callStarts': callStarts,
  'requestPhrases': requestPhrases,
  'requestStarts': requestStarts,
  'questionStarts': questionStarts,
  'questionPhrases': questionPhrases,
  'questionEnds': questionEnds,
  'invitePhrases': invitePhrases,
  'deadlinePhrases': deadlinePhrases,
  'notAskPhrases': notAskPhrases,
  'ackWords': ackWords,
  'thankWords': thankWords,
  'closerPhrases': closerPhrases,
  'stickerWords': stickerWords,
};

/// A message longer than this isn't only an ok, or only a goodbye.
const maxAckTokens = 8;
const maxCloserTokens = 10;

final _notWord = RegExp(r"[^\p{L}\p{M}\p{N}']+", unicode: true);

/// Lower-cased words, with phone keyboards' curly apostrophes straightened.
List<String> waitTokens(String text) => text
    .toLowerCase()
    .replaceAll('’', "'")
    .split(_notWord)
    .where((t) => t.isNotEmpty)
    .toList();

/// The same words as one string, for comparing and for remembering a phrase.
String waitPhrase(String text) => waitTokens(text).join(' ');

bool _hasQuestionMark(String text) =>
    text.contains('?') || text.contains('？') || text.contains('؟');

bool _startsWithDigit(String t) =>
    t.isNotEmpty && t.codeUnitAt(0) >= 0x30 && t.codeUnitAt(0) <= 0x39;

/// The phrase from [table] found in padded [s], if any.
String? _firstIn(List<String> table, String s) {
  for (final phrase in table) {
    if (s.contains(' $phrase ')) return phrase;
  }
  return null;
}

/// The phrase from [table] that [s] starts with, if any.
String? _firstAtStart(List<String> table, String s) {
  for (final phrase in table) {
    if (s.startsWith(' $phrase ')) return phrase;
  }
  return null;
}

/// The words of "by 5", "before 6pm" or "before the 4 o'clock", if any.
String? _numericDeadline(List<String> tokens) {
  for (var i = 0; i < tokens.length; i++) {
    if (tokens[i] != 'by' && tokens[i] != 'before') continue;
    for (var j = i + 1; j <= i + 2 && j < tokens.length; j++) {
      if (_startsWithDigit(tokens[j])) {
        return tokens.sublist(i, j + 1).join(' ');
      }
    }
  }
  return null;
}

/// What the rules alone make of [text]. Kept apart from the wording so it
/// reads line for line against WaitingIntent.kt.
WaitKind waitKindOf(String text) {
  final trimmed = text.trim();
  if (hasOneTimeCode(trimmed)) return WaitKind.code;
  final tokens = waitTokens(trimmed);
  if (tokens.isEmpty) {
    return _hasQuestionMark(trimmed) ? WaitKind.question : WaitKind.emojiOnly;
  }
  final s = ' ${tokens.join(' ')} ';
  if (tokens.length == 1 && stickerWords.contains(tokens.first)) {
    return WaitKind.emojiOnly;
  }

  if (_firstIn(callPhrases, s) != null) return WaitKind.call;
  if (callStarts.contains(tokens.first)) return WaitKind.call;

  final mayAsk = _firstIn(notAskPhrases, s) == null;
  if (mayAsk) {
    if (_firstIn(requestPhrases, s) != null) return WaitKind.request;
    if (requestStarts.contains(tokens.first)) return WaitKind.request;
    if (_hasQuestionMark(trimmed)) return WaitKind.question;
    if (_firstIn(invitePhrases, s) != null) return WaitKind.invite;
    if (_firstAtStart(questionStarts, s) != null) return WaitKind.question;
    if (_firstIn(questionPhrases, s) != null) return WaitKind.question;
    if (questionEnds.contains(tokens.last)) return WaitKind.question;
    if (_firstIn(deadlinePhrases, s) != null) return WaitKind.deadline;
    if (_numericDeadline(tokens) != null) return WaitKind.deadline;
  }

  if (tokens.length <= maxAckTokens && tokens.every(ackWords.contains)) {
    return WaitKind.ack;
  }
  if (tokens.length <= maxCloserTokens) {
    if (_firstIn(thankWords, s) != null) return WaitKind.ack;
    if (_firstIn(closerPhrases, s) != null) return WaitKind.closer;
  }
  return WaitKind.unsure;
}

const _longestQuote = 60;

String _clip(String s) => s.length <= _longestQuote
    ? s
    : '${s.substring(0, _longestQuote - 1).trimRight()}…';

/// The original words around [phrase], plus up to [after] more, cut at the
/// end of the sentence it's in.
String? _quote(String text, String phrase, {int after = 0}) {
  final wanted = phrase.split(' ');
  for (final clause in text.split(RegExp(r'[.!?。？\n;]+'))) {
    final words = clause
        .replaceAll('’', "'")
        .split(_notWord)
        .where((t) => t.isNotEmpty)
        .toList();
    final lower = [for (final w in words) w.toLowerCase()];
    for (var i = 0; i + wanted.length <= lower.length; i++) {
      var match = true;
      for (var j = 0; j < wanted.length; j++) {
        if (lower[i + j] != wanted[j]) {
          match = false;
          break;
        }
      }
      if (!match) continue;
      final end = (i + wanted.length + after).clamp(0, words.length);
      return _clip(words.sublist(i, end).join(' '));
    }
  }
  return null;
}

/// The last sentence with a question mark, as written: "You in?".
String _lastQuestion(String text) {
  final parts = RegExp(r'[^.!?。？؟\n]*[?？؟]').allMatches(text).toList();
  if (parts.isEmpty) return _clip(text.trim());
  return _clip(parts.last.group(0)!.trim());
}

String _where(bool isGroup, String? addressed) => switch (addressed) {
  'mentioned' => 'A group message that mentions you',
  'reply' => 'A reply right after you spoke in the group',
  _ => isGroup ? 'A group message' : 'A one-to-one chat',
};

/// The deadline [text] names, for "Why?".
String? _deadlineQuote(String text, List<String> tokens, String s) {
  final named = _firstIn(deadlinePhrases, s);
  if (named != null) return _quote(text, named, after: 2) ?? named;
  final numeric = _numericDeadline(tokens);
  if (numeric != null) return _quote(text, numeric, after: 2) ?? numeric;
  return null;
}

/// Whether [text] asks something of the owner, and why Echo thinks so.
/// [addressed] is the message's [Addressed] name.
WaitReason classifyWait(
  String text, {
  required bool isGroup,
  String? addressed,
}) {
  final trimmed = text.trim();
  final tokens = waitTokens(trimmed);
  final s = ' ${tokens.join(' ')} ';
  final kind = waitKindOf(trimmed);
  final signals = <String>[_where(isGroup, addressed)];

  void asked(String lead, String? quote) =>
      signals.add(quote == null ? lead : '$lead: “$quote”');

  String label;
  switch (kind) {
    case WaitKind.call:
      label = 'Asked you to call';
      final missed = _firstIn(const [
        'missed call',
        'missed voice call',
        'missed video call',
      ], s);
      if (missed != null) {
        signals.add('A missed call');
      } else {
        final phrase = _firstIn(callPhrases, s) ?? tokens.first;
        asked('Asks you to do something', _quote(trimmed, phrase, after: 2));
      }
    case WaitKind.request:
      label = 'Asked you for something';
      final phrase = _firstIn(requestPhrases, s) ?? tokens.first;
      asked('Asks for something', _quote(trimmed, phrase, after: 4));
    case WaitKind.question:
      label = 'Asked you a question';
      if (_hasQuestionMark(trimmed)) {
        final last = _lastQuestion(trimmed);
        signals.add(
          tokens.isEmpty
              ? 'Only a question mark'
              : 'Ends with a question: “$last”',
        );
      } else {
        final phrase =
            _firstAtStart(questionStarts, s) ??
            _firstIn(questionPhrases, s) ??
            tokens.last;
        asked('Asks a question', _quote(trimmed, phrase, after: 4));
      }
    case WaitKind.invite:
      label = 'Invited you';
      asked(
        'Invites you',
        _quote(trimmed, _firstIn(invitePhrases, s) ?? tokens.first, after: 3),
      );
    case WaitKind.deadline:
      label = 'Has a deadline for you';
    case WaitKind.ack:
      label = _firstIn(thankWords, s) != null
          ? 'Only a thank-you'
          : 'Just an ok';
    case WaitKind.closer:
      label = 'Closes the conversation';
    case WaitKind.emojiOnly:
      label = 'Only an emoji';
    case WaitKind.code:
      label = 'A one-time code';
    case WaitKind.unsure:
    case WaitKind.mention:
      label = 'Might need a reply';
  }

  final asks = switch (kind) {
    WaitKind.question ||
    WaitKind.request ||
    WaitKind.call ||
    WaitKind.invite ||
    WaitKind.deadline => true,
    _ => false,
  };
  if (asks && tokens.isNotEmpty) {
    final due = _deadlineQuote(trimmed, tokens, s);
    if (due != null) signals.add('Has a deadline: “$due”');
  }

  // A group message that names the owner: the mention is the headline.
  var finalKind = kind;
  if (asks && addressed == 'mentioned') {
    finalKind = WaitKind.mention;
    label = switch (kind) {
      WaitKind.question => 'Mentioned you with a question',
      WaitKind.call => 'Mentioned you, wants a call',
      WaitKind.invite => 'Mentioned you with an invite',
      WaitKind.deadline => 'Mentioned you with a deadline',
      _ => 'Mentioned you with a request',
    };
  }

  return WaitReason(
    kind: finalKind,
    needsReply: asks || kind == WaitKind.unsure,
    label: label,
    signals: signals,
  );
}

/// Whether Echo should read [kind] with the model: only the unclear ones.
bool isGreyZone(WaitKind kind) => kind == WaitKind.unsure;
