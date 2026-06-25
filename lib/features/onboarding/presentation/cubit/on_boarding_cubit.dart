import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  Future<void> saveUserNameAndFinish(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', name.trim());
    await prefs.setBool('onboarding_finished', true);
    emit(OnBoardingFinished());
  }
}
