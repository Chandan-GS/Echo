part of 'ask_ai_cubit.dart';

class ChatMessage {
  final String sender; // 'user' or 'echo'
  final String text;
  final bool isGenerating;
  final List<RawData> ragSources;

  /// A notice from Echo about Gemini (for example its daily limit), shown
  /// in a quieter style than an answer.
  final bool isNotice;

  ChatMessage({
    required this.sender,
    required this.text,
    this.isGenerating = false,
    this.ragSources = const [],
    this.isNotice = false,
  });

  ChatMessage copyWith({
    String? sender,
    String? text,
    bool? isGenerating,
    List<RawData>? ragSources,
  }) {
    return ChatMessage(
      sender: sender ?? this.sender,
      text: text ?? this.text,
      isGenerating: isGenerating ?? this.isGenerating,
      ragSources: ragSources ?? this.ragSources,
      isNotice: isNotice,
    );
  }
}

abstract class AskAiState {}

class AskAiInitial extends AskAiState {}

class AskAiMessageReceived extends AskAiState {
  final List<ChatMessage> messages;
  final bool isSearching;

  AskAiMessageReceived({required this.messages, this.isSearching = false});
}

class AskAiError extends AskAiState {
  final String message;
  AskAiError(this.message);
}
