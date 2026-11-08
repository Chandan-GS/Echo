import 'package:project_echo/features/echo/data/context/addressed.dart';

/// One message that wishes someone a happy birthday, seen in a group.
class WishLine {
  final String sender;
  final String text;
  final DateTime at;
  final String group;
  final String source;

  const WishLine({
    required this.sender,
    required this.text,
    required this.at,
    required this.group,
    this.source = '',
  });
}

/// A birthday spotted today across the owner's groups.
class BirthdaySighting {
  /// As written: "Neha", "Neha Sharma".
  final String name;
  final List<String> groups;

  /// Who wished, in the order they did.
  final List<String> wishers;

  const BirthdaySighting({
    required this.name,
    required this.groups,
    required this.wishers,
  });
}

/// A birthday wish, with who it's for if the message says.
class Wish {
  final String? name;
  const Wish(this.name);
}

const _latinWish =
    r'ha?p+y\s+(?:birth\s*da+y+s?|b[\s’'
    "'"
    r'-]?da+y+s?)'
    r'|\bhbd+\b'
    r'|many\s+(?:many\s+)?happy\s+returns(?:\s+of\s+the\s+day)?'
    r'|janam?\s*din\s+(?:ki\s+)?(?:(?:bahut|bohot|dher|hardik|saari)\s+)*'
    r'(?:mubara[kh]|badh?aa?i|shubh?\s*kam\w*|subh?\s*kam\w*)'
    r'|b(?:ir)?th\s*da+y\s+(?:ki\s+)?(?:(?:bahut|bohot|dher|saari)\s+)*'
    r'(?:mubara[kh]|badh?aa?i)'
    r'|janmdin\s+(?:ki\s+)?(?:(?:bahut|bohot|dher)\s+)*'
    r'(?:mubara[kh]|badh?aa?i|shubh?\s*kam\w*|subh?\s*kam\w*)';

const _hindiWish =
    r'हैप्पी\s+बर्थ\s*डे'
    r'|जन्म\s*दिन\s+(?:की\s+|का\s+)?(?:(?:बहुत|ढेर|हार्दिक|सारी)\s+)*'
    r'(?:मुबारक|बधाई|बधाइयां|शुभकामना\S*|शुभ\s*कामना\S*)';

final _wish = RegExp('$_latinWish|$_hindiWish', caseSensitive: false);

/// A party being planned, or a birthday that isn't today's. Takes precedence
/// over a wish phrase: "happy birthday party planning" is about no one.
final _notAWish = RegExp(
  r'\b(party|parties|plan|plans|planning|planned|surprise|gift|gifts|venue|'
  r'decor\w*|organi[sz]\w*|invite\w*|book(?:ing)?|cake\s+order|order\s+(?:a\s+)?cake|'
  r'belated|advance|yesterday|tomorrow|next\s+(?:week|month)|last\s+(?:week|month)|'
  r'kal|parso|kab\s+hai|kiska|kiski|kisko|when\s+is|whose|thank\s*you|thanks|thnx|'
  r'shukriya|dhanya?vaa?d)\b'
  r'|पार्टी|सरप्राइज|गिफ्ट|कब\s+है|किसका|किसकी|धन्यवाद|शुक्रिया',
  caseSensitive: false,
  unicode: true,
);

const _maxLength = 160;

/// Words that lead up to a name and are skipped: "to dear @Neha".
const _lead = {'to', 'dear', 'our', 'my', 'dearest', 'wala', 'wali', 'ho', 'हो'};

/// Words that end a name, or mean no one was named.
const _stop = {
  'you', 'u', 'me', 'all', 'everyone', 'everybody', 'again', 'once', 'friend',
  'friends', 'buddy', 'bro', 'brother', 'bhai', 'bhaiya', 'bhayya', 'sis',
  'sister', 'didi', 'di', 'boss', 'team', 'guys', 'sir', 'sirji', 'mam',
  'maam', 'madam', 'ji', 'jee', 'yaar', 'yar', 'dost', 'uncle', 'aunty',
  'auntie', 'party', 'celebration', 'cake', 'today', 'tomorrow', 'wish',
  'wishes', 'wishing', 'love', 'god', 'bless', 'have', 'hope', 'may', 'the',
  'a', 'an', 'this', 'that', 'is', 'was', 'in', 'on', 'at', 'for', 'of',
  'with', 'from', 'and', 'ka', 'ki', 'ke', 'ko', 'se', 'ne', 'mein', 'aur',
  'hai', 'ho', 'meri', 'mere', 'mera', 'humari', 'hamari', 'apko', 'aapko',
  'aap', 'tumhe', 'tujhe', 'tera', 'tumhara', 'aaj', 'nice', 'good', 'great',
  'big', 'best', 'sweet', 'lovely', 'guy', 'very', 'many', 'super', 'hello',
  'hi', 'hey', 'wow', 'bohot', 'bahut', 'को', 'जी', 'भाई', 'दीदी', 'का', 'की',
  'के', 'है', 'हो', 'और', 'आपको', 'तुम्हें', 'तुम्हे', 'आज', 'प्यारे', 'प्यारी',
};

final _edges = RegExp(r'^[^\p{L}\p{M}\p{N}]+|[^\p{L}\p{M}\p{N}]+$', unicode: true);
final _hasLetter = RegExp(r'\p{L}', unicode: true);
final _space = RegExp(r'\s+');

/// Reads [text] for a wish. Null if it isn't one; a [Wish] with no name if
/// it wishes someone without saying who.
Wish? matchWish(String text) {
  final t = text.trim();
  if (t.isEmpty || t.length > _maxLength) return null;
  if (t.contains('?')) return null;
  final lower = t.toLowerCase();
  if (lower.startsWith('forwarded') || _notAWish.hasMatch(lower)) return null;
  final m = _wish.firstMatch(t);
  if (m == null) return null;
  return Wish(
    _nameAfter(t.substring(m.end)) ?? _nameBefore(t.substring(0, m.start)),
  );
}

/// Whether the owner's own line [text] is a birthday wish.
bool isWishText(String text) => matchWish(text) != null;

String? _nameAfter(String rest) {
  final tokens = rest.trim().split(_space).where((s) => s.isNotEmpty).toList();
  final name = <String>[];
  var started = false;
  for (final raw in tokens) {
    final word = raw.replaceAll(_edges, '');
    if (word.isEmpty) {
      // An emoji or a lone "!" ends the name, but may come before one.
      if (name.isNotEmpty) break;
      continue;
    }
    final lower = word.toLowerCase();
    if (!started && _lead.contains(lower)) continue;
    if (_stop.contains(lower) || !_hasLetter.hasMatch(word)) break;
    started = true;
    name.add(word);
    // Anything stuck on the end of the word, like "Neha," or "Neha🎂".
    if (word.length != raw.length && !raw.startsWith('@')) break;
    if (name.length == 2) break;
  }
  return _validName(name);
}

String? _nameBefore(String head) {
  final tokens = head.trim().split(_space).where((s) => s.isNotEmpty).toList();
  final name = <String>[];
  var started = false;
  for (final raw in tokens.reversed) {
    final word = raw.replaceAll(_edges, '');
    if (word.isEmpty) {
      if (name.isNotEmpty) break;
      continue;
    }
    final lower = word.toLowerCase();
    // "Neha ko ...", "Neha ji ...": the name is the word before.
    if (!started && _stop.contains(lower)) {
      if (const {'ko', 'ji', 'जी', 'को', 'bhai', 'भाई', 'didi', 'दीदी', 'sir'}
          .contains(lower)) {
        continue;
      }
      break;
    }
    if (_stop.contains(lower) || !_hasLetter.hasMatch(word)) break;
    started = true;
    name.insert(0, word);
    if (name.length == 2) break;
  }
  return _validName(name);
}

String? _validName(List<String> words) {
  if (words.isEmpty) return null;
  final joined = words.join(' ');
  if (joined.runes.length < 2) return null;
  return joined;
}

/// The first word of a name, compared without case.
String _sameKey(String name) => name.split(_space).first.toLowerCase();

/// Birthdays people are wishing for in [lines] (today's group messages).
///
/// It takes two different people before Echo says anything: one person's
/// "happy birthday Neha" is too little to put on a card. A wish that names
/// no one counts only in a group where someone else named the person. Nobody
/// is wished for by themselves, and the owner's own birthday isn't a card.
List<BirthdaySighting> birthdaysFrom(
  Iterable<WishLine> lines, {
  Iterable<String> ownerNames = const [],
}) {
  final named = <String, _Pending>{};
  final unnamedByGroup = <String, List<String>>{};
  for (final line in lines) {
    final wish = matchWish(line.text);
    if (wish == null) continue;
    final name = wish.name;
    if (name == null) {
      (unnamedByGroup[line.group] ??= []).add(line.sender);
      continue;
    }
    if (mentionsAny(name, ownerNames)) continue;
    final key = _sameKey(name);
    if (_sameKey(line.sender) == key) continue;
    final p = named[key] ??= _Pending();
    if (name.length > p.name.length) p.name = name;
    if (!p.groups.contains(line.group)) p.groups.add(line.group);
    if (!p.wishers.contains(line.sender)) p.wishers.add(line.sender);
  }
  final out = <BirthdaySighting>[];
  for (final MapEntry(:key, :value) in named.entries) {
    for (final group in value.groups) {
      for (final sender in unnamedByGroup[group] ?? const <String>[]) {
        if (_sameKey(sender) != key && !value.wishers.contains(sender)) {
          value.wishers.add(sender);
        }
      }
    }
    if (value.wishers.length < 2) continue;
    out.add(
      BirthdaySighting(
        name: value.name,
        groups: value.groups,
        wishers: value.wishers,
      ),
    );
  }
  return out;
}

class _Pending {
  String name = '';
  final groups = <String>[];
  final wishers = <String>[];
}

/// The name's first word, for matching a sighting to a known person.
String birthdayKey(String name) => _sameKey(name);
