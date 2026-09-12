import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Marks that the next time the app reaches `EchoHomeScreen`, today's
/// briefing should start playing immediately rather than waiting for a tap —
/// used when the user reached the app via the notification's "Play" action or
/// by tapping the notification itself.
Future<void> _markPendingAutoplay() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('pending_autoplay', true);
}

/// Handles the daily-briefing notification's "Play" action being tapped while
/// the app process is fully terminated. Runs in its own background isolate,
/// mirroring the `alarmCallback` entry point in `schedule_service.dart`.
@pragma('vm:entry-point')
void notificationTapBackgroundHandler(NotificationResponse response) {
  _markPendingAutoplay();
}

class LocalNotificationService {
  static final LocalNotificationService _instance =
      LocalNotificationService._internal();

  factory LocalNotificationService() => _instance;

  LocalNotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('ic_notification');

    final DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    final InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsDarwin,
        );

    await flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
      // Tapping the notification body or its "Play" action while the app
      // process is alive (foreground or backgrounded) lands here.
      onDidReceiveNotificationResponse: (details) {
        _markPendingAutoplay();
      },
      // Tapping the "Play" action while the app is fully terminated lands
      // here instead, in a separate background isolate.
      onDidReceiveBackgroundNotificationResponse: notificationTapBackgroundHandler,
    );

    // On Android 13+ (API 33), posting ANY notification requires the runtime
    // POST_NOTIFICATIONS permission — separate from (and unrelated to) the
    // NotificationListenerService access granted during onboarding, which only
    // lets Echo *read* other apps' notifications. Without this, `show()` below
    // silently does nothing. A no-op on older Android/iOS.
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _initialized = true;
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'daily_briefing_channel',
          'Daily Briefing',
          channelDescription: 'Notifications for your daily AI briefing',
          importance: Importance.max,
          priority: Priority.high,
          showWhen: false,
          actions: const <AndroidNotificationAction>[
            AndroidNotificationAction(
              'play_briefing',
              'Play',
              showsUserInterface: true,
            ),
          ],
        );
    const DarwinNotificationDetails iOSPlatformChannelSpecifics =
        DarwinNotificationDetails();
    final NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
    );
    await flutterLocalNotificationsPlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: platformChannelSpecifics,
    );
  }
}
