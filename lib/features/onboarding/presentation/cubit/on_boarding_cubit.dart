import 'dart:io';
import 'package:flutter/material.dart';
import 'package:project_echo/core/services/analytics_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_echo/features/onboarding/data/first_look.dart';
import 'package:project_echo/features/onboarding/data/onboarding_personalization.dart';
import 'package:project_echo/features/onboarding/data/voice_preference.dart';

part 'on_boarding_state.dart';

/// The mornings the end of onboarding asks the owner to aim for, out of
/// their first seven.
const streakGoalMornings = 3;

/// The name each step is reported under in the onboarding funnel
/// (`onboarding_step`), in the order the steps come; null once finished.
String? onboardingStepName(OnBoardingState state) => switch (state) {
  OnBoardingInitial() => 'welcome',
  PermissionsStep() => 'access',
  FirstLookStep() => 'first_look',
  AppsStep() => 'apps',
  AiModeStep() => 'engine',
  NameInputStep() => 'name',
  PersonalizeStep() => 'personalise',
  VoiceStep() => 'voice',
  PreviewStep() => 'preview',
  StreakGoalStep() => 'streak_goal',
  OnBoardingFinished() => null,
};

const _stepOrder = [
  'welcome',
  'access',
  'first_look',
  'apps',
  'engine',
  'name',
  'personalise',
  'voice',
  'preview',
  'streak_goal',
];

/// Walks the owner through setup.
///
/// Every step reached is sent to the anonymous onboarding funnel
/// ([Analytics]), with `back` when it was reached going back; so are access
/// being granted, the first look heard to the end, each step skipped, and
/// setup finished. Only step names and small counts, never what Echo read.
///
/// The phone's flow puts the first look straight after access, so the owner
/// hears Echo within a minute; naming, personalising and the voice come
/// after and can each be skipped. [android] and [desktop] default to the
/// platform's, and are given in tests.
class OnBoardingCubit extends Cubit<OnBoardingState> {
  static const _platform = MethodChannel('project_echo/permissions');

  OnBoardingCubit({bool isFinished = false, bool? android, bool? desktop})
    : _android = android ?? Platform.isAndroid,
      _desktop = desktop ?? (Platform.isMacOS || Platform.isWindows),
      super(isFinished ? OnBoardingFinished() : OnBoardingInitial()) {
    if (!isFinished) Analytics.track('onboarding_step', {'step': 'welcome'});
  }

  final bool _android;
  final bool _desktop;

  /// Whether this flow ends with the streak goal (the phone's).
  bool get endsWithStreakGoal => _android;

  bool _accessGranted = false;
  bool _firstLookHeard = false;
  int _skipped = 0;

  /// Where the streak goal goes back to: the preview, or the voice step it
  /// was skipped from.
  OnBoardingState? _beforeGoal;

  @override
  void onChange(Change<OnBoardingState> change) {
    super.onChange(change);
    final from = onboardingStepName(change.currentState);
    final to = onboardingStepName(change.nextState);
    // Permissions are re-checked on every return to the app: same step.
    if (to == null || to == from) return;
    final back =
        from != null && _stepOrder.indexOf(to) < _stepOrder.indexOf(from);
    Analytics.track('onboarding_step', {'step': to, if (back) 'back': true});
  }

  void startOnboarding() {
    emit(OnBoardingInitial());
  }

  Future<void> completeWelcome() async {
    if (_desktop) {
      // Desktop builds don't have a notification/calendar/SMS capture layer
      // yet (that's phone-only for now), so the permissions step doesn't
      // apply — asking for permissions that don't exist here would be
      // dishonest UI. Skip straight to choosing the AI engine.
      emit(AiModeStep(selectedMode: null, isModelDownloaded: false));
      return;
    }
    await checkPermissions();
  }

  Future<void> checkPermissions() async {
    final notificationStatus = await _checkNotificationPermission();
    final calendarStatus = await Permission.calendarFullAccess.status;
    final alertsStatus = await Permission.notification.status;

    if (notificationStatus && !_accessGranted) {
      _accessGranted = true;
      Analytics.track('onboarding_access_granted');
    }
    emit(
      PermissionsStep(
        notificationGranted: notificationStatus,
        calendarGranted: calendarStatus.isGranted,
        alertsGranted: alertsStatus.isGranted,
      ),
    );
  }

  Future<bool> _checkNotificationPermission() async {
    try {
      final bool result = await _platform.invokeMethod(
        'checkNotificationPermission',
      );
      return result;
      // This custom channel only has a native handler on Android — desktop
      // (macOS/Windows) builds have nothing registered for it, which throws
      // MissingPluginException rather than PlatformException.
    } on MissingPluginException catch (_) {
      return false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<void> _requestNotificationPermission() async {
    try {
      await _platform.invokeMethod('requestNotificationPermission');
    } on MissingPluginException catch (_) {
      // ignore
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

  /// Asks to post Echo's briefing and reminders; once Android stops asking
  /// (denied for good), or to turn it off, that's in system settings.
  Future<void> toggleAlerts() async {
    final currentState = state;
    if (currentState is! PermissionsStep) return;
    final status = await Permission.notification.status;
    if (currentState.alertsGranted || status.isPermanentlyDenied) {
      await openAppSettings();
    } else if (!(await Permission.notification.request()).isGranted) {
      // Said no, or Android 12 and older (no question to show, notifications
      // switched off): the switch is in system settings.
      await openAppSettings();
    }
    await checkPermissions();
  }

  void completePermissions() {
    if (_android) {
      emit(FirstLookStep(autoPlay: !_firstLookHeard));
    } else {
      emit(AiModeStep(selectedMode: null, isModelDownloaded: false));
    }
  }

  /// The first look was read to the end; [kind] says only how full the
  /// phone was. Counted once.
  void firstLookHeard(FirstLookKind kind) {
    if (_firstLookHeard) return;
    _firstLookHeard = true;
    Analytics.track('onboarding_first_look_heard', {'kind': kind.name});
  }

  void completeFirstLook() {
    emit(AppsStep());
  }

  /// Back from the apps step. Echo doesn't read the first look again by
  /// itself once it's been heard.
  void goBackToFirstLook() {
    emit(FirstLookStep(autoPlay: !_firstLookHeard));
  }

  void completeApps() {
    emit(AiModeStep(selectedMode: null, isModelDownloaded: false));
  }

  void goBackToApps() {
    emit(AppsStep());
  }

  void _skip(String step) {
    _skipped++;
    Analytics.track('onboarding_step_skipped', {'step': step});
  }

  /// Skips naming: Echo greets the owner without a name (one given before,
  /// and kept, still counts).
  void skipName() {
    if (state is! NameInputStep) return;
    _skip('name');
    emit(PersonalizeStep());
  }

  /// Skips personalising: the tone, topics and briefing time stay as they
  /// are (professional, none, 7 AM, unless chosen before).
  Future<void> skipPersonalize() async {
    if (state is! PersonalizeStep) return;
    _skip('personalise');
    final prefs = await SharedPreferences.getInstance();
    emit(
      VoiceStep(
        name: prefs.getString('user_name') ?? '',
        tone: onboardingToneFromId(prefs.getString('briefing_tone')),
        interests: {
          for (final id in prefs.getStringList('briefing_interests') ?? [])
            ?onboardingInterestFromId(id),
        },
      ),
    );
  }

  /// Skips choosing a voice: Echo keeps the default one (or one chosen
  /// before). The phone goes on to the streak goal, as the preview is for
  /// hearing a chosen voice; elsewhere the preview plays in the default.
  Future<void> skipVoice() async {
    final current = state;
    if (current is! VoiceStep) return;
    _skip('voice');
    if (_android) {
      _beforeGoal = current;
      emit(StreakGoalStep());
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    emit(
      PreviewStep(
        name: current.name,
        tone: current.tone,
        interests: current.interests,
        voice: VoicePreference.read(prefs),
      ),
    );
  }

  /// Done with the preview: the phone shows the streak goal, other
  /// platforms finish.
  Future<void> completePreview() async {
    if (!_android) return finishOnboarding();
    _beforeGoal = state;
    emit(StreakGoalStep());
  }

  /// Back from the streak goal to where it was reached from.
  void goBackFromStreakGoal() {
    if (state is! StreakGoalStep) return;
    final before = _beforeGoal;
    if (before != null && (before is PreviewStep || before is VoiceStep)) {
      emit(before);
    } else {
      emit(PersonalizeStep());
    }
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
    Analytics.track('onboarding_completed', {'skipped': _skipped});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_finished', true);
    emit(OnBoardingFinished());
  }
}
