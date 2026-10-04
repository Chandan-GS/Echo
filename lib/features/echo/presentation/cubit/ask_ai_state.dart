part of 'ask_ai_cubit.dart';

enum MessageKind {
  /// A question, or Echo's answer.
  text,

  /// A note from Echo about Gemini (for example its daily limit), shown more
  /// quietly than an answer.
  notice,

  /// To-dos Echo just put on the list.
  added,

  /// A reply Echo drafted, waiting for the owner's yes.
  draft,
}

class ChatMessage {
  final String sender; // 'user' or 'echo'
  final String text;
  final bool isGenerating;
  final MessageKind kind;

  /// The notifications an answer was given, numbered from 1 as in its
  /// citations.
  final List<RawData> ragSources;

  /// How many notifications Echo looked through for an answer.
  final int checked;

  /// [MessageKind.added]: what went on the list, and whether it was undone.
  final List<TodoItem> added;
  final bool undone;

  /// [MessageKind.draft].
  final ReplyDraft? draft;

  /// An answer that names things to do which aren't on the list yet.
  final bool addable;

  ChatMessage({
    required this.sender,
    required this.text,
    this.isGenerating = false,
    this.kind = MessageKind.text,
    this.ragSources = const [],
    this.checked = 0,
    this.added = const [],
    this.undone = false,
    this.draft,
    this.addable = false,
  });

  bool get isUser => sender == 'user';
  bool get isNotice => kind == MessageKind.notice;

  /// The sources the answer cites, in order of first mention.
  List<RawData> get cited => citedSources(text, ragSources);

  /// What the answer is about: what it cites, or everything it was given.
  List<RawData> get about => cited.isNotEmpty ? cited : ragSources;

  /// How many things the answer says there are to do.
  int get todos => todoCount(text);

  ChatMessage copyWith({
    String? text,
    bool? isGenerating,
    List<RawData>? ragSources,
    bool? undone,
    ReplyDraft? draft,
    bool? addable,
  }) {
    return ChatMessage(
      sender: sender,
      text: text ?? this.text,
      isGenerating: isGenerating ?? this.isGenerating,
      kind: kind,
      ragSources: ragSources ?? this.ragSources,
      checked: checked,
      added: added,
      undone: undone ?? this.undone,
      draft: draft ?? this.draft,
      addable: addable ?? this.addable,
    );
  }
}

enum DraftStatus {
  writing,
  ready,
  sending,
  sent,
  written,
  picker,
  copied,
  dismissed,
}

/// A message Echo wrote for the owner to send to [to].
class ReplyDraft {
  final RawData to;
  final String text;
  final ReplyRoute route;
  final DraftStatus status;

  /// When it went out (or was handed to the chat app).
  final DateTime? doneAt;

  const ReplyDraft({
    required this.to,
    required this.text,
    required this.route,
    required this.status,
    this.doneAt,
  });

  /// "College gang" for a group, else the person.
  String get chatName => to.isGroup && (to.threadTitle?.isNotEmpty ?? false)
      ? to.threadTitle!
      : to.sender;

  bool get open => status == DraftStatus.ready;

  ReplyDraft copyWith({
    String? text,
    ReplyRoute? route,
    DraftStatus? status,
    DateTime? doneAt,
  }) => ReplyDraft(
    to: to,
    text: text ?? this.text,
    route: route ?? this.route,
    status: status ?? this.status,
    doneAt: doneAt ?? this.doneAt,
  );
}

/// Echo at work on a question: how many notifications it's reading, then how
/// many of them matter.
class AskProgress {
  final int reading;
  final int? found;
  const AskProgress(this.reading, [this.found]);
}

abstract class AskAiState {}

class AskAiInitial extends AskAiState {}

class AskAiMessageReceived extends AskAiState {
  final List<ChatMessage> messages;
  final bool isSearching;
  final AskProgress? progress;

  AskAiMessageReceived({
    required this.messages,
    this.isSearching = false,
    this.progress,
  });
}

class AskAiError extends AskAiState {
  final String message;
  AskAiError(this.message);
}
