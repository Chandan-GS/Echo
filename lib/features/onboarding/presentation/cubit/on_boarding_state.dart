part of 'on_boarding_cubit.dart';

@immutable
sealed class OnBoardingState {}

final class OnBoardingInitial extends OnBoardingState {}

final class PermissionsStep extends OnBoardingState {
  final bool notificationGranted;
  final bool calendarGranted;
  final bool smsGranted;

  PermissionsStep({
    required this.notificationGranted,
    required this.calendarGranted,
    required this.smsGranted,
  });

  bool get canContinue => notificationGranted && calendarGranted;
}

final class AiModeStep extends OnBoardingState {
  final String? selectedMode; // 'offline' or 'online'
  final bool isModelDownloaded;

  AiModeStep({this.selectedMode, this.isModelDownloaded = false});
}

final class NameInputStep extends OnBoardingState {}

/// Captures how Echo should speak and what the user cares about.
final class PersonalizeStep extends OnBoardingState {}

/// Lets the user audition and pick Echo's spoken voice. Carries the prior
/// selections so the following [PreviewStep] can be assembled.
final class VoiceStep extends OnBoardingState {
  final String name;
  final OnboardingTone tone;
  final Set<OnboardingInterest> interests;

  VoiceStep({
    required this.name,
    required this.tone,
    required this.interests,
  });
}

/// Plays a scripted, personalized sample briefing (on-device TTS) so the user
/// experiences the payoff before finishing setup.
final class PreviewStep extends OnBoardingState {
  final String name;
  final OnboardingTone tone;
  final Set<OnboardingInterest> interests;
  final VoicePreference voice;

  PreviewStep({
    required this.name,
    required this.tone,
    required this.interests,
    required this.voice,
  });
}

final class OnBoardingFinished extends OnBoardingState {}
