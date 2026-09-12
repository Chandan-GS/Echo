import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_echo/features/onboarding/data/onboarding_personalization.dart';
import 'package:project_echo/features/onboarding/data/voice_preference.dart';

part 'on_boarding_state.dart';

class OnBoardingCubit extends Cubit<OnBoardingState> {
  static const _platform = MethodChannel('project_echo/permissions');

  OnBoardingCubit({bool isFinished = false})
    : super(isFinished ? OnBoardingFinished() : OnBoardingInitial());

  void startOnboarding() {
    emit(OnBoardingInitial());
  }

  Future<void> completeWelcome() async {
    await checkPermissions();
  }

  Future<void> checkPermissions() async {
    final notificationStatus = await _checkNotificationPermission();
    final calendarStatus = await Permission.calendarFullAccess.status;
    final smsStatus = await Permission.sms.status;

    emit(
      PermissionsStep(
        notificationGranted: notificationStatus,
        calendarGranted: calendarStatus.isGranted,
        smsGranted: smsStatus.isGranted,
      ),
    );
  }

  Future<bool> _checkNotificationPermission() async {
    try {
      final bool result = await _platform.invokeMethod(
        'checkNotificationPermission',
      );
      return result;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<void> _requestNotificationPermission() async {
    try {
      await _platform.invokeMethod('requestNotificationPermission');
    } on PlatformException catch (_) {
      // ignore
    }
  }

  Future<void> toggleNotification() async {
    await _requestNotificationPermission();
  }

  Future<void> toggleCalendar() async {
    final currentState = state;
    if (currentState is PermissionsStep) {
      if (currentState.calendarGranted) {
        await openAppSettings();
      } else {
        final status = await Permission.calendarFullAccess.request();
        if (!status.isGranted) {
          await openAppSettings();
        }
      }
      await checkPermissions();
    }
  }

  Future<void> toggleSms() async {
    final currentState = state;
    if (currentState is PermissionsStep) {
      if (currentState.smsGranted) {
        await openAppSettings();
      } else {
        final status = await Permission.sms.request();
        if (!status.isGranted) {
          await openAppSettings();
        }
      }
      await checkPermissions();
    }
  }

  void completePermissions() {
    emit(AiModeStep(selectedMode: null, isModelDownloaded: false));
  }

  void selectAiMode(String mode) {
    final currentState = state;
    if (currentState is AiModeStep) {
      emit(
        AiModeStep(
          selectedMode: mode,
          isModelDownloaded: currentState.isModelDownloaded,
        ),
      );
    }
  }

  void setModelDownloaded(bool downloaded) {
    final currentState = state;
    if (currentState is AiModeStep) {
      emit(
        AiModeStep(
          selectedMode: currentState.selectedMode,
          isModelDownloaded: downloaded,
        ),
      );
    }
  }

  void completeAiMode() {
    emit(NameInputStep());
  }

  void goBackToAiMode() {
    emit(AiModeStep());
  }

  /// Saves the user's name and advances to the personalization step (no longer
  /// the last step — the reward/preview now comes before finishing).
  Future<void> saveUserNameAndContinue(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', name.trim());
    emit(PersonalizeStep());
  }

  void goBackToName() {
    emit(NameInputStep());
  }

  /// Persists the tone + interests and advances to the voice picker.
  Future<void> completePersonalize({
    required OnboardingTone tone,
    required Set<OnboardingInterest> interests,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('briefing_tone', tone.id);
    await prefs.setStringList(
      'briefing_interests',
      interests.map((e) => e.id).toList(),
    );
    final name = prefs.getString('user_name') ?? '';
    emit(VoiceStep(name: name, tone: tone, interests: interests));
  }

  void goBackToPersonalize() {
    emit(PersonalizeStep());
  }

  /// Persists the shaped voice and advances to the spoken preview.
  Future<void> completeVoice(VoicePreference voice) async {
    final current = state;
    if (current is! VoiceStep) return;
    final prefs = await SharedPreferences.getInstance();
    await voice.persist(prefs);
    emit(
      PreviewStep(
        name: current.name,
        tone: current.tone,
        interests: current.interests,
        voice: voice,
      ),
    );
  }

  void goBackToVoice() {
    final current = state;
    if (current is PreviewStep) {
      emit(
        VoiceStep(
          name: current.name,
          tone: current.tone,
          interests: current.interests,
        ),
      );
    }
  }

  Future<void> finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_finished', true);
    emit(OnBoardingFinished());
  }
}
