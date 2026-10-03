package com.chandangs.echo

import android.content.Intent
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import com.chandangs.echo_native.NotificationBuffer
import org.json.JSONObject

class EchoNotificationListenerService : NotificationListenerService() {
    companion object {
        const val ACTION_NEW_NOTIFICATION = "com.chandangs.echo.NEW_NOTIFICATION"
        const val EXTRA_NOTIFICATION_DATA = "notification_data"

        private var lastProcessedText: String = ""
        private var lastProcessedPackage: String = ""
        private var lastProcessedTime: Long = 0

        var isFlutterListening: Boolean = false

        /** The connected listener, for reading what's in the shade right now. */
        @Volatile var instance: EchoNotificationListenerService? = null
    }

    private val seen by lazy { ConversationReader.Seen(applicationContext) }

    override fun onListenerConnected() {
        super.onListenerConnected()
        instance = this
    }

    override fun onListenerDisconnected() {
        instance = null
        super.onListenerDisconnected()
    }

    /** Packages with a notification in the shade, busiest first. */
    fun activePackages(): List<String> = try {
        activeNotifications.orEmpty()
            .filter { !it.isOngoing && it.packageName != packageName }
            .groupingBy { it.packageName }
            .eachCount()
            .entries
            .sortedByDescending { it.value }
            .map { it.key }
    } catch (e: Exception) {
        emptyList()
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

        // Apps switched off in Vault → Apps Echo hears are never captured.
        if (!AppAccessRules.hears(applicationContext, packageName)) {
            return
        }

        // Filter out group summaries and WhatsApp "X new messages" spam
        if ((sbn.notification?.flags ?: 0) and android.app.Notification.FLAG_GROUP_SUMMARY != 0) {
            return
        }

        // Chats: every new message in the thread, with its own sender and time.
        val conversation = ConversationReader.read(sbn)
        if (conversation != null) {
            val now = System.currentTimeMillis()
            val fresh = seen.unseen(conversation, now)
            seen.markSeen(conversation)
            for (m in fresh) {
                // Apps mark the owner's own messages with no sender, or with
                // the same name they give the owner.
                val fromMe = m.sender == null || m.sender == conversation.selfName
                val json = JSONObject()
                json.put("source", mapPackageToSource(packageName))
                json.put("sender", if (fromMe) "" else m.sender)
                json.put("content", m.text)
                json.put("timestamp", m.time)
                json.put("packageName", packageName)
                json.put("thread", conversation.thread)
                json.put("threadTitle", conversation.title)
                json.put("isGroup", conversation.isGroup)
                // The owner's own messages only tell Echo when they last spoke.
                json.put("fromMe", fromMe)
                conversation.selfName?.let { json.put("selfName", it) }
                emit(json)
            }
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

        // An expanded notification (a long email, a long message) carries
        // its whole text separately; the plain text is only the first line.
        val bigText = extras.getCharSequence(android.app.Notification.EXTRA_BIG_TEXT)?.toString()?.trim().orEmpty()

        val json = JSONObject()
        json.put("source", mapPackageToSource(packageName))
        json.put("sender", cleanTitle)
        json.put("content", if (bigText.length > text.length) bigText else text)
        json.put("timestamp", currentTime)
        json.put("packageName", packageName)
        json.put("thread", ConversationReader.threadId(sbn, cleanTitle))
        emit(json)
    }

    /**
     * Tapping a notification or swiping it away is the clearest sign of what
     * matters to the owner. Only those two are kept: when an app clears its
     * own notification (read elsewhere, opened from the launcher) there's no
     * telling which it was.
     */
    override fun onNotificationRemoved(
        sbn: StatusBarNotification?,
        rankingMap: RankingMap?,
        reason: Int,
    ) {
        super.onNotificationRemoved(sbn, rankingMap, reason)
        if (sbn == null || sbn.isOngoing) return
        val action = when (reason) {
            REASON_CLICK -> "opened"
            REASON_CANCEL -> "dismissed"
            else -> return
        }
        val packageName = sbn.packageName ?: return
        if (packageName == applicationContext.packageName) return
        if (!AppAccessRules.hears(applicationContext, packageName)) return
        if ((sbn.notification?.flags ?: 0) and android.app.Notification.FLAG_GROUP_SUMMARY != 0) return

        val json = JSONObject()
        json.put("kind", "engagement")
        json.put("action", action)
        json.put("packageName", packageName)
        json.put("source", mapPackageToSource(packageName))
        json.put("thread", ConversationReader.read(sbn)?.thread ?: ConversationReader.threadId(sbn))
        json.put("timestamp", System.currentTimeMillis())
        emit(json)
    }

    private fun emit(json: JSONObject) {
        val jsonString = json.toString()
        Log.d("EchoNotification", "Captured from ${json.optString("packageName")}")

        // 1. Buffer to SharedPreferences ONLY if Flutter is not actively listening
        if (!isFlutterListening) {
            NotificationBuffer.append(applicationContext, jsonString)
        }

        // 2. Broadcast to MainActivity if active
        val intent = Intent(ACTION_NEW_NOTIFICATION)
        intent.putExtra(EXTRA_NOTIFICATION_DATA, jsonString)
        intent.setPackage(applicationContext.packageName)
        sendBroadcast(intent)
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
}
