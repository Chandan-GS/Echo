package com.chandangs.echo

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import org.json.JSONObject

/**
 * Reminders set on Home, in Ask Echo or on a to-do. A windowed alarm: Android
 * delivers it within ten minutes of the time, which needs no exact-alarm
 * permission (Echo deliberately doesn't hold one), unlike a plain inexact
 * alarm that may land an hour late.
 *
 * The notification quotes what it's about and offers what comes next: open
 * that chat, snooze ten minutes, or tick the to-do off.
 */
object Reminders {
    private const val WINDOW_MS = 10 * 60 * 1000L
    private const val SNOOZE_MS = 10 * 60 * 1000L
    private const val CHANNEL = "echo_reminders"
    private const val DAY_MS = 24 * 60 * 60 * 1000L

    /** The Dart side's list of reminders (see reminders.dart). */
    private const val STORE_KEY = "flutter.echo_reminders_v1"

    const val ACTION_SNOOZE = "com.chandangs.echo.REMINDER_SNOOZE"
    const val ACTION_DONE = "com.chandangs.echo.REMINDER_DONE"

    /** What a reminder says and what it's about; carried by its alarm. */
    data class Reminder(
        val id: Int,
        val key: String,
        val title: String,
        val body: String,
        /** The to-do it's on, or -1. */
        val todoId: Int,
        /** The chat it came from, or null. */
        val thread: String?,
    ) {
        fun into(intent: Intent): Intent = intent
            .putExtra("id", id)
            .putExtra("key", key)
            .putExtra("title", title)
            .putExtra("body", body)
            .putExtra("todoId", todoId)
            .putExtra("thread", thread)

        companion object {
            fun from(intent: Intent): Reminder? {
                val title = intent.getStringExtra("title") ?: return null
                return Reminder(
                    id = intent.getIntExtra("id", 0),
                    key = intent.getStringExtra("key") ?: "",
                    title = title,
                    body = intent.getStringExtra("body") ?: "",
                    todoId = intent.getIntExtra("todoId", -1),
                    thread = intent.getStringExtra("thread"),
                )
            }
        }
    }

    fun set(context: Context, reminder: Reminder, at: Long) {
        val alarms = context.getSystemService(AlarmManager::class.java)
        alarms.setWindow(AlarmManager.RTC_WAKEUP, at, WINDOW_MS, alarm(context, reminder))
    }

    fun cancel(context: Context, id: Int) {
        context.getSystemService(AlarmManager::class.java)
            .cancel(alarm(context, Reminder(id, "", "", "", -1, null)))
    }

    private fun alarm(context: Context, reminder: Reminder): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            reminder.id,
            reminder.into(Intent(context, ReminderReceiver::class.java)),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    fun post(context: Context, reminder: Reminder) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL, "Reminders", NotificationManager.IMPORTANCE_HIGH)
                .apply { description = "Reminders you set in Echo" },
        )
        val id = reminder.id
        val open = context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
            PendingIntent.getActivity(context, id, it, PendingIntent.FLAG_IMMUTABLE)
        }
        val builder = Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(reminder.title)
            .setContentText(reminder.body)
            .setStyle(Notification.BigTextStyle().bigText(reminder.body))
            .setAutoCancel(true)
            .setContentIntent(open)
        reminder.thread?.let { ReplyActions.openChatIntent(context, it, id) }?.let {
            builder.addAction(action(context, "Open chat", it))
        }
        builder.addAction(action(context, "Snooze 10 min", own(context, ACTION_SNOOZE, reminder)))
        if (reminder.todoId >= 0) {
            builder.addAction(action(context, "Done", own(context, ACTION_DONE, reminder)))
        }
        manager.notify(id, builder.build())
    }

    private fun action(context: Context, label: String, intent: PendingIntent) =
        Notification.Action.Builder(
            Icon.createWithResource(context, R.drawable.ic_notification),
            label,
            intent,
        ).build()

    /** A button the receiver below handles; distinct per reminder and action. */
    private fun own(context: Context, action: String, reminder: Reminder): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            reminder.id * 4 + if (action == ACTION_SNOOZE) 1 else 2,
            reminder.into(Intent(context, ReminderReceiver::class.java).setAction(action)),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    fun snooze(context: Context, reminder: Reminder) {
        val at = System.currentTimeMillis() + SNOOZE_MS
        set(context, reminder, at)
        updateStore(context, reminder.key) { it?.put("at", at) }
    }

    fun done(context: Context, reminder: Reminder) {
        if (reminder.todoId >= 0) {
            TodoWidgetData.setDone(context, reminder.todoId, true)
            EchoTodoWidgetProvider.updateAll(context)
            EchoTodoOrbWidgetProvider.updateAll(context)
        }
        updateStore(context, reminder.key) { null }
    }

    /** Whether the to-do [reminder] is on has been ticked off since it was set. */
    fun alreadyDone(context: Context, reminder: Reminder): Boolean =
        reminder.todoId >= 0 &&
            TodoWidgetData.all(context).any { it.id == reminder.todoId && it.done }

    /**
     * Sets every reminder again after the phone restarts or Echo is updated,
     * both of which clear alarms. One whose time passed while the phone was
     * off comes a minute later rather than not at all.
     */
    fun restoreAll(context: Context) {
        val all = try {
            JSONObject(WidgetData.prefs(context).getString(STORE_KEY, null) ?: "{}")
        } catch (e: Exception) {
            return
        }
        val now = System.currentTimeMillis()
        for (key in all.keys()) {
            val r = all.optJSONObject(key) ?: continue
            val at = r.optLong("at")
            val title = r.optString("title")
            // Older entries lack the text; and a day late is no reminder.
            if (title.isEmpty() || at < now - DAY_MS) continue
            set(
                context,
                Reminder(
                    id = r.optInt("id"),
                    key = key,
                    title = title,
                    body = r.optString("body"),
                    todoId = r.optInt("todoId", -1),
                    thread = if (r.isNull("thread")) null else r.optString("thread"),
                ),
                maxOf(at, now + 60_000L),
            )
        }
    }

    /** Changes (or, given null, removes) [key]'s entry in the Dart side's list. */
    private fun updateStore(context: Context, key: String, change: (JSONObject?) -> JSONObject?) {
        if (key.isEmpty()) return
        val prefs = WidgetData.prefs(context)
        val all = try {
            JSONObject(prefs.getString(STORE_KEY, null) ?: "{}")
        } catch (e: Exception) {
            JSONObject()
        }
        val next = change(all.optJSONObject(key))
        if (next == null) all.remove(key) else all.put(key, next)
        prefs.edit().putString(STORE_KEY, all.toString()).apply()
    }
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            Reminders.restoreAll(context)
            return
        }
        val reminder = Reminders.Reminder.from(intent) ?: return
        when (intent.action) {
            Reminders.ACTION_SNOOZE -> {
                context.getSystemService(android.app.NotificationManager::class.java).cancel(reminder.id)
                Reminders.snooze(context, reminder)
            }
            Reminders.ACTION_DONE -> {
                context.getSystemService(android.app.NotificationManager::class.java).cancel(reminder.id)
                Reminders.done(context, reminder)
            }
            // The alarm itself.
            else -> if (!Reminders.alreadyDone(context, reminder)) Reminders.post(context, reminder)
        }
    }
}
