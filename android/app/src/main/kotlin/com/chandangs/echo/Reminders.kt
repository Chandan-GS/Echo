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
import android.net.Uri
import org.json.JSONObject

/**
 * Reminders set on Home, in Ask Echo or on a to-do. A windowed alarm: Android
 * delivers it within ten minutes of the time, which needs no exact-alarm
 * permission (Echo deliberately doesn't hold one), unlike a plain inexact
 * alarm that may land an hour late. A windowed alarm waits out Doze, though,
 * so each reminder also has an inexact allow-while-idle alarm behind it for a
 * phone left idle; whichever goes off first cancels the other.
 *
 * The notification quotes what it's about and offers what comes next: open
 * that chat, snooze ten minutes, or tick the to-do off. Tapping it opens the
 * to-do list.
 */
object Reminders {
    private const val WINDOW_MS = 10 * 60 * 1000L
    private const val SNOOZE_MS = 10 * 60 * 1000L
    private const val CHANNEL = "echo_reminders"

    /** The Dart side's list of reminders (see reminders.dart). */
    private const val STORE_KEY = "flutter.echo_reminders_v1"

    /**
     * When each reminder last went off, by its key. Native-only, in a file of
     * its own, so the Dart side rewriting its list can't lose it.
     */
    private const val FIRED_PREFS = "echo_reminders_fired"

    /** Where tapping a reminder lands: Flutter routes an intent's data to go_router. */
    private val TODO_ROUTE: Uri = Uri.parse("echo://app/todo")

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
        alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, alarm(context, reminder, idle = true))
    }

    fun cancel(context: Context, id: Int) {
        val alarms = context.getSystemService(AlarmManager::class.java)
        val blank = Reminder(id, "", "", "", -1, null)
        alarms.cancel(alarm(context, blank))
        alarms.cancel(alarm(context, blank, idle = true))
    }

    /** A reminder's alarm: the windowed one, or ([idle]) the one for Doze. */
    private fun alarm(context: Context, reminder: Reminder, idle: Boolean = false): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            if (idle) reminder.id * 4 + 3 else reminder.id,
            reminder.into(Intent(context, ReminderReceiver::class.java)),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    /** The alarm for [reminder] has gone off: note it, and show it unless its to-do is done. */
    fun fire(context: Context, reminder: Reminder) {
        // The other of its two alarms, so it doesn't come twice.
        cancel(context, reminder.id)
        if (reminder.key.isNotEmpty()) {
            markFired(context, listOf(reminder.key))
        }
        if (!alreadyDone(context, reminder)) post(context, reminder)
    }

    /** Records [keys] as having gone off now, forgetting ones long past. */
    private fun markFired(context: Context, keys: List<String>) {
        if (keys.isEmpty()) return
        val now = System.currentTimeMillis()
        val kept = ReminderRules.prune(firedAt(context), now) + keys.map { it to now }
        val editor = context.getSharedPreferences(FIRED_PREFS, Context.MODE_PRIVATE).edit().clear()
        for ((key, at) in kept) editor.putLong(key, at)
        editor.apply()
    }

    private fun firedAt(context: Context): Map<String, Long> =
        context.getSharedPreferences(FIRED_PREFS, Context.MODE_PRIVATE).all
            .mapNotNull { (k, v) -> (v as? Long)?.let { k to it } }
            .toMap()

    fun post(context: Context, reminder: Reminder) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL, "Reminders", NotificationManager.IMPORTANCE_HIGH)
                .apply { description = "Reminders you set in Echo" },
        )
        val id = reminder.id
        // Not before onboarding is done: the to-do list isn't there yet, and
        // the plain launch goes wherever Echo would start.
        val onboarded = WidgetData.prefs(context).getBoolean("flutter.onboarding_finished", false)
        val launch = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        if (onboarded) launch.setAction(Intent.ACTION_VIEW).setData(TODO_ROUTE)
        val open = PendingIntent.getActivity(
            context,
            id * 4 + 3,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(reminder.title)
            .setContentText(reminder.body)
            .setStyle(Notification.BigTextStyle().bigText(reminder.body))
            .setCategory(Notification.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .setContentIntent(open)
        reminder.thread?.let { ReplyActions.openChatIntent(context, it, id * 4) }?.let {
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
     * Sets reminders again after the phone restarts ([afterBoot]), which
     * clears alarms, or after Echo is updated. Only ones that haven't gone
     * off: one whose time passed while the phone was off comes once, a
     * minute later, rather than not at all (see [ReminderRules.plan]).
     */
    fun restoreAll(context: Context, afterBoot: Boolean) {
        val all = try {
            JSONObject(WidgetData.prefs(context).getString(STORE_KEY, null) ?: "{}")
        } catch (e: Exception) {
            return
        }
        val entries = all.keys().asSequence()
            .mapNotNull { key -> all.optJSONObject(key)?.let { key to it } }
            .toMap()
        val plan = ReminderRules.plan(
            entries.map { (key, r) ->
                ReminderRules.Stored(key, r.optLong("at"), r.optString("title").isNotEmpty())
            },
            firedAt(context),
            System.currentTimeMillis(),
            afterBoot,
        )
        for ((key, at) in plan.set) {
            val r = entries.getValue(key)
            set(
                context,
                Reminder(
                    id = r.optInt("id"),
                    key = key,
                    title = r.optString("title"),
                    body = r.optString("body"),
                    todoId = r.optInt("todoId", -1),
                    thread = if (r.isNull("thread")) null else r.optString("thread"),
                ),
                at,
            )
        }
        markFired(context, plan.markFired)
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
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED -> return Reminders.restoreAll(context, afterBoot = true)
            Intent.ACTION_MY_PACKAGE_REPLACED -> return Reminders.restoreAll(context, afterBoot = false)
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
            else -> Reminders.fire(context, reminder)
        }
    }
}
