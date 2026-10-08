import 'package:project_echo/features/echo/data/context/addressed.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';

/// What the owner asked Echo to do rather than tell: put things on the list,
/// or answer someone. Spotted locally, so a plain question never pays for it.
class AskIntent {
  /// "add them to my list", "put that on my to-do".
  final bool addToList;

  /// "reply to Rahul that I'll bring it", "tell Neha I'm running late".
  final ReplyRequest? reply;

  const AskIntent({this.addToList = false, this.reply});

  bool get isEmpty => !addToList && reply == null;
}

/// Who to answer, and what to say when the owner said it ([gist]).
class ReplyRequest {
  final RawData to;
  final String? gist;
  const ReplyRequest(this.to, this.gist);
}

final _addToList = RegExp(
  r"\b(add|put)\b.*\b(list|to-?dos?)\b|\badd (them|these|those|it|that|this)\b",
  caseSensitive: false,
);

final _replyVerb = RegExp(
  r"\b(reply|respond|answer|tell|text|message|let)\b",
  caseSensitive: false,
);

/// Words between a name and what to say: "Rahul *that* I'll …", "Neha *know
/// that* …", "Mom*:* …".
final _lead = RegExp(
  r"^\s*(?:know\s+)?(?:that\b|saying\b|to say\b|:|,|-)?\s*",
  caseSensitive: false,
);

/// [chats] are recent chat messages, newest first; the person named must be
/// one of their senders or chats.
AskIntent parseIntent(String text, List<RawData> chats) =>
    AskIntent(addToList: _addToList.hasMatch(text), reply: _reply(text, chats));

/// The person has to follow the verb ("tell Rahul …", "reply to Rahul …"),
/// so "tell me what Rahul said" stays a question.
ReplyRequest? _reply(String text, List<RawData> chats) {
  for (final verb in _replyVerb.allMatches(text)) {
    final after = text
        .substring(verb.end)
        .replaceFirst(
          RegExp(r'^\s+(?:back\s+)?(?:to\s+)?', caseSensitive: false),
          '',
        );
    for (final e in chats) {
      for (final name in {e.sender, e.threadTitle ?? ''}) {
        final end = _nameEnd(after, name);
        if (end == null) continue;
        final gist = after.substring(end).replaceFirst(_lead, '').trim();
        return ReplyRequest(e, gist.isEmpty ? null : gist);
      }
    }
  }
  return null;
}

/// Where [name] ends if [text] starts with it as whole words ("Rahul", or
/// "Rahul Sharma" by its first name), or null.
int? _nameEnd(String text, String name) {
  final full = name.trim();
  if (full.length < 2) return null;
  for (final candidate in {full, full.split(RegExp(r'\s+')).first}) {
    if (candidate.length < 3 && candidate != full) continue;
    final m = RegExp(
      '^${RegExp.escape(candidate)}(?![\\p{L}\\p{N}])',
      caseSensitive: false,
      unicode: true,
    ).firstMatch(text);
    if (m != null) return m.end;
  }
  return null;
}

/// Chat messages worth answering, newest first: those meant for the owner,
/// then the rest.
List<RawData> replyCandidates(Iterable<RawData> entries) {
  final chats =
      entries.where((e) => e.addressed != null && e.thread != null).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return [
    ...chats.where((e) => Addressed.parse(e.addressed) != Addressed.group),
    ...chats.where((e) => Addressed.parse(e.addressed) == Addressed.group),
  ];
}
