package com.example.project_echo

import android.content.Context
import android.content.Intent
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

class EchoNotificationListenerService : NotificationListenerService() {
    companion object {
        const val PREFS_NAME = "echo_notification_prefs"
        const val BUFFER_KEY = "notification_buffer"
        const val ACTION_NEW_NOTIFICATION = "com.example.project_echo.NEW_NOTIFICATION"
        const val EXTRA_NOTIFICATION_DATA = "notification_data"

        private var lastProcessedText: String = ""
        private var lastProcessedPackage: String = ""
        private var lastProcessedTime: Long = 0

        var isFlutterListening: Boolean = false
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        if (sbn == null) return

        val packageName = sbn.packageName ?: return
        val extras = sbn.notification?.extras ?: return
        
        val title = extras.getCharSequence("android.title")?.toString() ?: ""
        val text = extras.getCharSequence("android.text")?.toString() ?: ""
        
        if (title.isEmpty() && text.isEmpty()) return
        
        // Filter out system and ongoing notifications
        if (sbn.isOngoing || packageName == "android" || packageName == "com.android.systemui") {
            return
        }

        // Filter out group summaries and WhatsApp "X new messages" spam
        if ((sbn.notification?.flags ?: 0) and android.app.Notification.FLAG_GROUP_SUMMARY != 0) {
            return
        }
        
        val textLower = text.lowercase()
        if (textLower.matches(Regex("\\d+\\s+new messages.*")) || textLower == "checking for new messages") {
            return
        }

        val currentTime = System.currentTimeMillis()
        if (text.isNotEmpty() && text == lastProcessedText && packageName == lastProcessedPackage && (currentTime - lastProcessedTime) < 2000) {
            return // Duplicate detected within 2 seconds
        }

        lastProcessedText = text
        lastProcessedPackage = packageName
        lastProcessedTime = currentTime

        // Clean up WhatsApp summary prefixes
        var cleanTitle = title
        if (packageName.contains("whatsapp", ignoreCase = true) && title.startsWith("WhatsApp: ", ignoreCase = true)) {
            cleanTitle = title.substring(10).trim()
        }

        val json = JSONObject()
        json.put("source", mapPackageToSource(packageName))
        json.put("sender", cleanTitle)
        json.put("content", text)
        json.put("timestamp", System.currentTimeMillis())
        json.put("packageName", packageName)

        val jsonString = json.toString()
        Log.d("EchoNotification", "Captured: $jsonString")

        // 1. Buffer to SharedPreferences ONLY if Flutter is not actively listening
        if (!isFlutterListening) {
            bufferNotification(jsonString)
        }

        // 2. Broadcast to MainActivity if active
        val intent = Intent(ACTION_NEW_NOTIFICATION)
        intent.putExtra(EXTRA_NOTIFICATION_DATA, jsonString)
        intent.setPackage(applicationContext.packageName)
        sendBroadcast(intent)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        super.onNotificationRemoved(sbn)
    }

    private fun mapPackageToSource(pkg: String): String {
        return when {
            pkg.contains("whatsapp") -> "WhatsApp"
            pkg.contains("slack") -> "Slack"
            pkg.contains("calendar") -> "Calendar"
            pkg.contains("gmail") || pkg.contains("email") || pkg.contains("android.gm") || pkg.contains("mail") -> "Gmail"
            pkg.contains("mms") || pkg.contains("sms") || pkg.contains("messaging") -> "SMS"
            else -> {
                val parts = pkg.split(".")
                if (parts.size > 1) parts.last().replaceFirstChar { it.uppercase() } else pkg
            }
        }
    }

    @Synchronized
    private fun bufferNotification(data: String) {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val currentBufferStr = prefs.getString(BUFFER_KEY, "[]")
        try {
            val array = JSONArray(currentBufferStr)
            array.put(JSONObject(data))
            prefs.edit().putString(BUFFER_KEY, array.toString()).apply()
        } catch (e: Exception) {
            Log.e("EchoNotification", "Error buffering notification", e)
            val newArray = JSONArray()
            newArray.put(JSONObject(data))
            prefs.edit().putString(BUFFER_KEY, newArray.toString()).apply()
        }
    }
}
