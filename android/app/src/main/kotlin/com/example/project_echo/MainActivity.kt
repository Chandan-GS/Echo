package com.example.project_echo

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.provider.Settings
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray

class MainActivity : FlutterActivity() {
    private val PERMISSIONS_CHANNEL = "project_echo/permissions"
    private val NOTIFICATIONS_METHOD_CHANNEL = "project_echo/notifications"
    private val NOTIFICATIONS_EVENT_CHANNEL = "project_echo/notification_stream"
    private val WIDGET_CHANNEL = "project_echo/widget"

    private var notificationReceiver: BroadcastReceiver? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        // Must run before super.onCreate(), which is what boots the Flutter
        // engine / runs Dart main() — the autoplay flag needs to already be
        // written by the time EchoHomeScreen reads it.
        handleWidgetLaunchIntent(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleWidgetLaunchIntent(intent)
    }

    /** If this launch came from tapping the home-screen widget, mark today's
     * briefing to autoplay — the same one-shot flag the notification "Play"
     * action uses, so EchoHomeScreen needs no widget-specific handling. */
    private fun handleWidgetLaunchIntent(intent: Intent?) {
        if (intent?.getBooleanExtra(EchoBriefingWidgetProvider.EXTRA_AUTOPLAY, false) == true) {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit().putBoolean("flutter.pending_autoplay", true).apply()
            intent.removeExtra(EchoBriefingWidgetProvider.EXTRA_AUTOPLAY)
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "refresh" -> {
                    EchoBriefingWidgetProvider.updateAll(this)
                    EchoStreakWidgetProvider.updateAll(this)
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PERMISSIONS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkNotificationPermission" -> {
                    result.success(isNotificationServiceEnabled())
                }
                "requestNotificationPermission" -> {
                    openNotificationSettings()
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFICATIONS_METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "fetchTodayCalendarEvents" -> {
                    if (checkSelfPermission(android.Manifest.permission.READ_CALENDAR) == android.content.pm.PackageManager.PERMISSION_GRANTED) {
                        result.success(getTodayCalendarEvents())
                    } else {
                        result.success("[]")
                    }
                }
                "drainBuffer" -> {
                    val prefs = getSharedPreferences(EchoNotificationListenerService.PREFS_NAME, Context.MODE_PRIVATE)
                    val bufferStr = prefs.getString(EchoNotificationListenerService.BUFFER_KEY, "[]")
                    // Clear the buffer after reading
                    prefs.edit().putString(EchoNotificationListenerService.BUFFER_KEY, "[]").apply()
                    result.success(bufferStr)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFICATIONS_EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )
    }

    override fun onResume() {
        super.onResume()
        EchoNotificationListenerService.isFlutterListening = true
        notificationReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val data = intent?.getStringExtra(EchoNotificationListenerService.EXTRA_NOTIFICATION_DATA)
                if (data != null) {
                    eventSink?.success(data)
                }
            }
        }
        val filter = IntentFilter(EchoNotificationListenerService.ACTION_NEW_NOTIFICATION)
        registerReceiver(notificationReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
    }

    override fun onPause() {
        super.onPause()
        EchoNotificationListenerService.isFlutterListening = false
        notificationReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (e: Exception) {}
            notificationReceiver = null
        }
    }

    private fun isNotificationServiceEnabled(): Boolean {
        val pkgName = packageName
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
        if (!flat.isNullOrEmpty()) {
            val names = flat.split(":")
            for (name in names) {
                val cn = ComponentName.unflattenFromString(name)
                if (cn != null) {
                    if (pkgName == cn.packageName) {
                        return true
                    }
                }
            }
        }
        return false
    }

    private fun openNotificationSettings() {
        try {
            val intent = Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        } catch (e: Exception) {
            val intent = Intent(Settings.ACTION_SETTINGS)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        }
    }

    private fun getTodayCalendarEvents(): String {
        val calendar = java.util.Calendar.getInstance()
        calendar.set(java.util.Calendar.HOUR_OF_DAY, 0)
        calendar.set(java.util.Calendar.MINUTE, 0)
        calendar.set(java.util.Calendar.SECOND, 0)
        val startOfDay = calendar.timeInMillis

        calendar.set(java.util.Calendar.HOUR_OF_DAY, 23)
        calendar.set(java.util.Calendar.MINUTE, 59)
        calendar.set(java.util.Calendar.SECOND, 59)
        val endOfDay = calendar.timeInMillis

        val projection = arrayOf(
            android.provider.CalendarContract.Events.TITLE,
            android.provider.CalendarContract.Events.DTSTART,
            android.provider.CalendarContract.Events.DTEND,
            android.provider.CalendarContract.Events.DESCRIPTION
        )

        val selection = "${android.provider.CalendarContract.Events.DTSTART} >= ? AND ${android.provider.CalendarContract.Events.DTSTART} <= ?"
        val selectionArgs = arrayOf(startOfDay.toString(), endOfDay.toString())

        val cursor = try {
            contentResolver.query(
                android.provider.CalendarContract.Events.CONTENT_URI,
                projection,
                selection,
                selectionArgs,
                "${android.provider.CalendarContract.Events.DTSTART} ASC"
            )
        } catch (e: Exception) {
            null
        }

        val array = org.json.JSONArray()
        cursor?.use {
            val titleIdx = it.getColumnIndex(android.provider.CalendarContract.Events.TITLE)
            val startIdx = it.getColumnIndex(android.provider.CalendarContract.Events.DTSTART)
            val endIdx = it.getColumnIndex(android.provider.CalendarContract.Events.DTEND)
            val descIdx = it.getColumnIndex(android.provider.CalendarContract.Events.DESCRIPTION)

            while (it.moveToNext()) {
                val title = if (titleIdx != -1) it.getString(titleIdx) else ""
                val start = if (startIdx != -1) it.getLong(startIdx) else 0L
                val end = if (endIdx != -1) it.getLong(endIdx) else 0L
                val desc = if (descIdx != -1) it.getString(descIdx) else ""

                if (!title.isNullOrEmpty()) {
                    val json = org.json.JSONObject()
                    json.put("source", "Calendar")
                    json.put("sender", title)
                    val dateFormat = java.text.SimpleDateFormat("h:mm a", java.util.Locale.getDefault())
                    val timeString = "${dateFormat.format(java.util.Date(start))} - ${dateFormat.format(java.util.Date(end))}"
                    val contentStr = if (desc.isNullOrEmpty()) timeString else "$timeString\n$desc"
                    
                    json.put("content", contentStr)
                    json.put("timestamp", start)
                    array.put(json)
                }
            }
        }
        return array.toString()
    }
}
