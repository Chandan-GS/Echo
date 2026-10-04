import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

/// Echo asks to post notifications in onboarding, and again where they're
/// needed — setting a reminder, adding a briefing time — for anyone who
/// skipped it or set up before it was asked there. Never at launch, and never
/// once Android has stopped showing the question (that's system settings).
abstract final class NotifyPermission {
  static Future<void> askIfNeeded() async {
    if (!Platform.isAndroid) return;
    try {
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
    } catch (_) {
      // No activity to ask from (a background isolate): ask another time.
    }
  }
}
