part of 'briefing_cubit.dart';

abstract class BriefingState {}

class BriefingInitial extends BriefingState {}

class BriefingGenerating extends BriefingState {
  final String partial;
  BriefingGenerating({this.partial = ''});
}

class BriefingCached extends BriefingState {
  final String rawText;
  final String ttsText;
  BriefingCached({required this.rawText, required this.ttsText});
}

class BriefingReady extends BriefingState {
  final String rawText;
  final String ttsText;
  BriefingReady({required this.rawText, required this.ttsText});
}

class BriefingError extends BriefingState {
  final String message;

  /// Gemini's daily limit stopped it (Home then says when it resets).
  final bool limitReached;

  BriefingError(this.message, {this.limitReached = false});
}
