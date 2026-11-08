import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:project_echo/core/services/local_notification_service.dart';
import 'package:project_echo/features/echo/data/wrap/evening_wrap.dart';
import 'package:project_echo/features/echo/data/wrap/wrap_store.dart';
import 'package:project_echo/features/settings/data/evening_wrap.dart';
import 'package:project_echo/features/settings/data/tone_voice.dart';

/// Posts the evening wrap, built by [WrapStore] like the wrap screen. All of
/// it runs on the phone; nothing here touches a model or the network.
class EveningWrapService {
  EveningWrapService._();

  static const _notificationId = 91000;

  /// Tonight's wrap at [now], or null if the data can't be read (the Settings
  /// preview then shows nothing rather than a guess).
  static Future<EveningWrap?> _build(DateTime now) async {
    try {
      return await WrapStore.build(now);
    } catch (e) {
      debugPrint('Evening wrap couldn\'t be built: $e');
      return null;
    }
  }

  /// What the notification would say at [now].
  static Future<EveningWrapText?> tonight(DateTime now) async {
    final wrap = await _build(now);
    return wrap == null ? null : wrapNotificationText(wrap, await currentTone());
  }

  /// Posts tonight's wrap, silently: one quiet line in the shade, and tapping
  /// it opens Echo. With nothing heard yet there's nothing to say.
  static Future<void> post(DateTime now) async {
    final wrap = await _build(now);
    if (wrap == null || wrap.noData) return;
    final text = wrapNotificationText(wrap, await currentTone());
    final service = LocalNotificationService();
    await service.init();
    await service.flutterLocalNotificationsPlugin.show(
      id: _notificationId,
      title: text.title,
      body: text.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          // A channel's importance can't be lowered once it exists, so this
          // id must only ever be used at low importance.
          'evening_wrap_quiet',
          'Evening wrap',
          channelDescription: 'Who’s still waiting, and tomorrow’s to-dos',
          importance: Importance.low,
          priority: Priority.low,
          playSound: false,
          enableVibration: false,
          styleInformation: BigTextStyleInformation(text.body),
        ),
        iOS: const DarwinNotificationDetails(presentSound: false),
      ),
      payload: eveningWrapPayload,
    );
  }
}
