/// Who a chat message was meant for. Worked out once, when it arrives, from
/// the thread it's in — so the briefing, the to-do list and Ask Echo can tell
/// "Rahul asked you" from forty messages of group chatter.
enum Addressed {
  /// A one-to-one chat: everything in it is for the owner.
  direct,

  /// A group message that names the owner.
  mentioned,

  /// A group message that came right after the owner spoke there.
  reply,

  /// Group chat that isn't aimed at the owner.
  group;

  static Addressed? parse(String? name) {
    for (final a in values) {
      if (a.name == name) return a;
    }
    return null;
  }

  /// How much more a briefing should care, on top of its usual ranking.
  double get weight => switch (this) {
    mentioned => 0.8,
    reply => 0.6,
    direct => 0.4,
    group => -0.3,
  };

  /// How a prompt describes it after the app name.
  String get promptNote => switch (this) {
    direct => 'to you',
    mentioned => 'mentions you',
    reply => 'replying to you',
    group => 'not addressed to you',
  };
}

/// How long after the owner speaks in a group a message still reads as an
/// answer, and how many other messages may come in between.
const replyWindow = Duration(minutes: 30);
const replyMaxBetween = 4;

/// Classifies one incoming chat message. [mySpokeAt] is when the owner last
/// wrote in this thread, and [messagesSince] how many messages others have
/// sent there since.
Addressed addressedFor({
  required bool isGroup,
  required String content,
  required DateTime at,
  required Iterable<String> myNames,
  DateTime? mySpokeAt,
  int messagesSince = 0,
}) {
  if (!isGroup) return Addressed.direct;
  if (mentionsAny(content, myNames)) return Addressed.mentioned;
  if (mySpokeAt != null &&
      !at.isBefore(mySpokeAt) &&
      at.difference(mySpokeAt) <= replyWindow &&
      messagesSince <= replyMaxBetween) {
    return Addressed.reply;
  }
  return Addressed.group;
}

/// Whether [text] names any of [names] as a whole word ("@Chandan", "chandan,"
/// — not "Chandana"). Names shorter than three letters are ignored: they'd
/// match too much by accident.
bool mentionsAny(String text, Iterable<String> names) {
  for (final raw in names) {
    final name = raw.trim();
    if (name.length < 3) continue;
    final pattern = RegExp(
      '(?<![\\p{L}\\p{N}])@?${RegExp.escape(name)}(?![\\p{L}\\p{N}])',
      caseSensitive: false,
      unicode: true,
    );
    if (pattern.hasMatch(text)) return true;
  }
  return false;
}

/// The names that mean the owner: the one given in onboarding and its first
/// word, plus whatever chat apps call them. "You" and "Me" are how apps label
/// the owner's own messages, not names anyone would write.
Set<String> ownerNames(String? userName, Iterable<String> learned) {
  const generic = {'you', 'me', 'myself'};
  final names = <String>{};
  void add(String? n) {
    final t = n?.trim() ?? '';
    if (t.isEmpty || generic.contains(t.toLowerCase())) return;
    names.add(t);
  }

  add(userName);
  add(userName?.trim().split(RegExp(r'\s+')).first);
  learned.forEach(add);
  return names;
}
