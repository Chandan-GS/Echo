package com.chandangs.echo

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * "Remind me at 7:40" from Ask Echo. A windowed alarm: Android delivers it
 * within ten minutes of the time, which needs no exact-alarm permission (Echo
 * deliberately doesn't hold one), unlike a plain inexact alarm that may land
 * an hour late.
 */
object Reminders {
    private const val WINDOW_MS = 10 * 60 * 1000L
    private const val CHANNEL = "echo_reminders"

    fun set(context: Context, id: Int, at: Long, title: String, body: String) {
        val alarms = context.getSystemService(AlarmManager::class.java)
        alarms.setWindow(AlarmManager.RTC_WAKEUP, at, WINDOW_MS, pending(context, id, title, body))
    }

    fun cancel(context: Context, id: Int) {
        context.getSystemService(AlarmManager::class.java).cancel(pending(context, id, "", ""))
    }

    private fun pending(context: Context, id: Int, title: String, body: String): PendingIntent {
        val intent = Intent(context, ReminderReceiver::class.java)
            .putExtra("id", id)
            .putExtra("title", title)
            .putExtra("body", body)
        return PendingIntent.getBroadcast(
            context,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    fun post(context: Context, id: Int, title: String, body: String) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL, "Reminders", NotificationManager.IMPORTANCE_HIGH)
                .apply { description = "Reminders you set in Ask Echo" },
        )
        val open = context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
            PendingIntent.getActivity(context, id, it, PendingIntent.FLAG_IMMUTABLE)
        }
        val notification = Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(open)
            .build()
        manager.notify(id, notification)
    }
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Reminders.post(
            context,
            intent.getIntExtra("id", 0),
            intent.getStringExtra("title") ?: return,
            intent.getStringExtra("body") ?: "",
        )
    }
}
