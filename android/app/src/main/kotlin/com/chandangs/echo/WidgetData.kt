package com.chandangs.echo

import android.content.Context
import android.content.SharedPreferences
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
    private const val PREFS = "FlutterSharedPreferences"

    // Day-tracker states.
    const val FUTURE = 0
    const val MISSED = 1
    const val DONE = 2
    const val TODAY = 3

    fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

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

    /** "Ready — tap to play" once today's briefing is cached, else a live
     * countdown to the next scheduled briefing. */
    fun statusText(prefs: SharedPreferences): String {
        if (isReadyToday(prefs)) return "Ready — tap to play"
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
