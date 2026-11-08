package com.chandangs.echo

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.Log
import java.util.Calendar

/**
 * Keeps the widgets current when nothing else is running: a redraw just after
 * midnight (today becomes tomorrow, the ages move up a band) and every few
 * minutes while the next to-do's countdown is close. Alarms are inexact and
 * don't wake the phone, so a sleeping phone costs nothing; the widgets catch
 * up the moment it wakes.
 */
object WidgetClock {
    private const val TAG = "EchoWidgets"
    private const val ACTION_TICK = "com.chandangs.echo.WIDGET_TICK"
    private const val REQUEST_CODE = 9100

    /** How close a to-do must be before the countdown is worth updating. */
    private const val COUNTDOWN_WATCH_MINUTES = 180
    private const val COUNTDOWN_STEP_MS = 5 * 60_000L

    /** Sets (or moves) the one pending redraw. Skipped when no widget is placed. */
    fun arm(context: Context) {
        try {
            val alarms = context.getSystemService(AlarmManager::class.java) ?: return
            val pending = tickIntent(context)
            if (!anyPlaced(context)) {
                alarms.cancel(pending)
                return
            }
            alarms.set(AlarmManager.RTC, nextRefreshAt(context), pending)
        } catch (e: Exception) {
            Log.w(TAG, "Couldn't set the widgets' next refresh: ${e.message}")
        }
    }

    private fun tickIntent(context: Context): PendingIntent {
        val intent = Intent(context, EchoWidgetRefreshReceiver::class.java).setAction(ACTION_TICK)
        return PendingIntent.getBroadcast(
            context, REQUEST_CODE, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun anyPlaced(context: Context): Boolean {
        val manager = AppWidgetManager.getInstance(context)
        return listOf(
            EchoBriefingWidgetProvider::class.java,
            EchoStreakWidgetProvider::class.java,
            EchoTodoWidgetProvider::class.java,
            EchoTodoOrbWidgetProvider::class.java,
        ).any { manager.getAppWidgetIds(ComponentName(context, it)).isNotEmpty() }
    }

    private fun nextRefreshAt(context: Context): Long {
        val now = Calendar.getInstance()
        val midnight = (now.clone() as Calendar).apply {
            add(Calendar.DAY_OF_YEAR, 1)
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 5)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
        val next = TodoWidgetData.next(context)?.takeIf { it.time != null } ?: return midnight
        val minutesLeft = next.sort - (now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE))
        if (minutesLeft <= 0) return midnight
        val tick = if (minutesLeft <= COUNTDOWN_WATCH_MINUTES) {
            now.timeInMillis + COUNTDOWN_STEP_MS
        } else {
            now.timeInMillis + (minutesLeft - COUNTDOWN_WATCH_MINUTES) * 60_000L
        }
        return minOf(tick, midnight)
    }
}

/**
 * Redraws the widgets at midnight (see [WidgetClock]) and after anything
 * that changes the date or clears alarms: a reboot, an app update, a new
 * time zone or a clock change.
 */
class EchoWidgetRefreshReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        WidgetData.refreshAll(context)
    }
}
