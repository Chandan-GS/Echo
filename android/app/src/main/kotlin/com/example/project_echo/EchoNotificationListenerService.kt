package com.example.project_echo

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

class EchoNotificationListenerService : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        Log.d("EchoNotification", "Notification posted: " + sbn?.packageName)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        super.onNotificationRemoved(sbn)
        Log.d("EchoNotification", "Notification removed: " + sbn?.packageName)
    }
}
