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

  bool get canContinue => notificationGranted && calendarGranted && smsGranted;
}

final class AiModeStep extends OnBoardingState {
  final String? selectedMode; // 'offline' or 'online'
  final bool isModelDownloaded;

  AiModeStep({this.selectedMode, this.isModelDownloaded = false});
}

final class OnBoardingFinished extends OnBoardingState {}
