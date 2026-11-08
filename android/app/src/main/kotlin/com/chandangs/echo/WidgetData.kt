package com.chandangs.echo

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.provider.Settings
import android.util.Log
import android.widget.RemoteViews
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * Shared reads/computations for Echo's home-screen widgets, straight from the
 * `FlutterSharedPreferences` file the Dart side writes. Everything the widgets
 * show (streak, status, and the day-by-day tracker) is derived here against the
 * device's *current* clock, so a widget stays accurate even if the app hasn't
 * run in days.
 */
object WidgetData {
    private const val TAG = "EchoWidgets"
    private const val PREFS = "FlutterSharedPreferences"

    /** Set on a widget's tap; see MainActivity.handleWidgetLaunchIntent. */
    const val EXTRA_ROUTE = "widget_route"
    const val EXTRA_SENDER = "widget_sender"
    const val EXTRA_SOURCE = "widget_source"
    const val ROUTE_TODAY = "/echo"
    const val ROUTE_TODO = "/todo"
    const val ROUTE_PERSON = "/person"

    // Day-tracker states.
    const val FUTURE = 0
    const val MISSED = 1
    const val DONE = 2
    const val TODAY = 3

    fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Redraws every widget and sets the next refresh. Safe from anywhere. */
    fun refreshAll(context: Context) {
        for (update in listOf<() -> Unit>(
            { EchoBriefingWidgetProvider.updateAll(context) },
            { EchoStreakWidgetProvider.updateAll(context) },
            { EchoTodoWidgetProvider.updateAll(context) },
            { EchoTodoOrbWidgetProvider.updateAll(context) },
        )) {
            try {
                update()
            } catch (e: Exception) {
                Log.e(TAG, "A widget failed to refresh", e)
            }
        }
        WidgetClock.arm(context)
    }

    /** Opens the app at [route]. [requestCode] must be unique per target. */
    fun openRoute(
        context: Context,
        requestCode: Int,
        route: String,
        sender: String? = null,
        source: String? = null,
        autoplay: Boolean = false,
    ): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_ROUTE, route)
            sender?.let { putExtra(EXTRA_SENDER, it) }
            source?.let { putExtra(EXTRA_SOURCE, it) }
            if (autoplay) putExtra(EchoBriefingWidgetProvider.EXTRA_AUTOPLAY, true)
        }
        return PendingIntent.getActivity(
            context, requestCode, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /** A widget's size, in dp, as it sits on a portrait home screen. */
    data class WidgetSize(val widthDp: Int, val heightDp: Int)

    fun size(manager: AppWidgetManager, widgetId: Int, defaultWidth: Int, defaultHeight: Int): WidgetSize {
        val options = manager.getAppWidgetOptions(widgetId)
        val w = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
        val h = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)
        return WidgetSize(if (w > 0) w else defaultWidth, if (h > 0) h else defaultHeight)
    }

    /**
     * Sets a colour from a colour resource. Android 12+ lets the launcher
     * resolve it, so it follows light / dark even after the phone switches;
     * older versions use the colour for the mode at draw time.
     */
    fun setColorRes(context: Context, views: RemoteViews, id: Int, method: String, colorRes: Int) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            views.setColor(id, method, colorRes)
        } else {
            views.setInt(id, method, context.getColor(colorRes))
        }
    }

    /** Whether Echo may read notifications at all (it can't know who's waiting otherwise). */
    fun listening(context: Context): Boolean {
        val flat = Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners")
        if (flat.isNullOrEmpty()) return false
        return flat.split(":").any { ComponentName.unflattenFromString(it)?.packageName == context.packageName }
    }

    /** What the in-app previews show, read the same way the widgets read it. */
    fun previewState(context: Context): Map<String, Any?> {
        val now = System.currentTimeMillis()
        val waiting = WaitingWidgetData.load(context, now)
        val today = TodoWidgetData.today(context)
        val tomorrow = TodoWidgetData.tomorrow(context)
        val next = TodoWidgetData.next(context)
        return mapOf(
            "date" to shortDate(),
            "ready" to isReadyToday(prefs(context)),
            "briefingOn" to briefingOn(prefs(context)),
            "listening" to listening(context),
            "waitingKnown" to waiting.known,
            "waiting" to waiting.people.take(4).map {
                mapOf(
                    "name" to WaitingWidgetData.shortName(it),
                    "source" to it.source,
                    "age" to WaitingWidgetData.ageBand(it.since, now),
                    "progress" to WaitingWidgetData.ageProgress(it.since, now).toDouble(),
                    "since" to WaitingWidgetData.shortSince(it.since, now),
                )
            },
            "waitingCount" to waiting.people.size,
            "oldestDays" to WaitingWidgetData.oldestDays(waiting, now),
            "hasList" to TodoWidgetData.hasList(context),
            "dueToday" to today.count { !it.done },
            "todosToday" to today.size,
            "tomorrow" to tomorrow.size,
            "next" to next?.let {
                mapOf(
                    "title" to it.title,
                    "due" to TodoWidgetData.dueLabel(it),
                    "countdown" to TodoWidgetData.countdown(it),
                    "app" to it.app,
                )
            },
            "tomorrowTitle" to tomorrow.firstOrNull()?.title,
            "owesYou" to readLongOrInt(prefs(context), "flutter.widget_owes_you_v1").toInt(),
        )
    }

    /** Today's date for the widgets' headers, e.g. "Fri 7 Nov". */
    fun shortDate(): String = SimpleDateFormat("EEE d MMM", Locale.getDefault()).format(Date())

    /** shared_preferences stores Dart ints as Long, but this has varied — try
     * both so a bad type can never crash a widget update. */
    fun readLongOrInt(prefs: SharedPreferences, key: String): Long {
        return try {
            prefs.getLong(key, 0L)
        } catch (e: ClassCastException) {
            try {
                prefs.getInt(key, 0).toLong()
            } catch (e2: ClassCastException) {
                0L
            }
        }
    }

    fun streak(prefs: SharedPreferences): Int =
        readLongOrInt(prefs, "flutter.streak_current").toInt()

    private fun dateKey(date: Date): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(date)

    private fun todayKey(): String = dateKey(Date())

    fun isReadyToday(prefs: SharedPreferences): Boolean =
        prefs.getString("flutter.cached_briefing_date", null) == todayKey()

    /** Whether the owner has the morning briefing on (Settings → Briefing). */
    fun briefingOn(prefs: SharedPreferences): Boolean =
        prefs.getBoolean("flutter.briefing_enabled", true)

    /** "Ready — tap to play" once today's briefing is cached, else a live
     * countdown to the next scheduled briefing. Empty when the briefing is
     * off: none is coming, so there's nothing to count down to. */
    fun statusText(prefs: SharedPreferences): String {
        if (isReadyToday(prefs)) return "Ready — tap to play"
        if (!briefingOn(prefs)) return ""
        val target = readLongOrInt(prefs, "flutter.next_briefing_epoch_ms")
        if (target <= 0L) return "Your next briefing is scheduled soon"
        val remaining = target - System.currentTimeMillis()
        if (remaining <= 0L) return "Ready any moment now"
        val totalMinutes = remaining / 60_000
        val h = totalMinutes / 60
        val m = totalMinutes % 60
        return if (h > 0) "Ready in ${h}h ${m}m" else "Ready in ${m}m"
    }

    private fun heardSet(prefs: SharedPreferences): Set<String> {
        val raw = prefs.getString("flutter.streak_heard_csv", "") ?: ""
        if (raw.isEmpty()) return emptySet()
        return raw.split(",").filter { it.isNotBlank() }.toSet()
    }

    /**
     * The current Mon→Sun week as 7 states. A past unheard day only counts as
     * MISSED if it's after the user's first-ever heard day (so a brand-new
     * user's past week shows empty, not an ugly wall of red).
     */
    fun weekStates(prefs: SharedPreferences): IntArray {
        val heard = heardSet(prefs)
        val earliest = heard.minOrNull()
        val today = todayKey()

        val cal = Calendar.getInstance()
        cal.firstDayOfWeek = Calendar.MONDAY
        cal.set(Calendar.DAY_OF_WEEK, Calendar.MONDAY)
        cal.set(Calendar.HOUR_OF_DAY, 12)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)

        val states = IntArray(7)
        for (i in 0 until 7) {
            val key = dateKey(cal.time)
            states[i] = when {
                heard.contains(key) -> DONE
                key == today -> TODAY
                key < today && earliest != null && key > earliest -> MISSED
                else -> FUTURE
            }
            cal.add(Calendar.DAY_OF_MONTH, 1)
        }
        return states
    }
}
