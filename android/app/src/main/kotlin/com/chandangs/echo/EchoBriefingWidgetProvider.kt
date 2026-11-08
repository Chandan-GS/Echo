package com.chandangs.echo

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.os.Bundle
import android.util.Log
import android.view.View
import android.widget.RemoteViews

/**
 * "Today": who's waiting and what's due, with the week of briefings below.
 * Tap the card to open Today; the round button plays the briefing, or shows
 * it's still to come (and goes away when the briefing is off). Computed from stored prefs against the device clock
 * (see [WidgetData]), so it stays right even if the app hasn't run in days.
 * (The class keeps its old name so widgets already on home screens carry on.)
 */
class EchoBriefingWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val TAG = "EchoBriefingWidget"
        private const val WIDGET_REQUEST = 4_000_000
        const val EXTRA_AUTOPLAY = "autoplay_from_widget"

        /** Below this there's no room for the week. */
        private const val TRACK_MIN_HEIGHT_DP = 130

        private val DOT_IDS = intArrayOf(
            R.id.daydot_0, R.id.daydot_1, R.id.daydot_2, R.id.daydot_3,
            R.id.daydot_4, R.id.daydot_5, R.id.daydot_6,
        )

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, EchoBriefingWidgetProvider::class.java)
            )
            if (ids.isNotEmpty()) {
                EchoBriefingWidgetProvider().onUpdate(context, manager, ids)
            }
        }

        private fun dotDrawable(state: Int): Int = when (state) {
            WidgetData.DONE -> R.drawable.day_done
            WidgetData.MISSED -> R.drawable.day_missed
            WidgetData.TODAY -> R.drawable.day_today
            else -> R.drawable.day_future
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (id in appWidgetIds) {
            try {
                updateWidget(context, appWidgetManager, id)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to update widget $id", e)
            }
        }
        WidgetClock.arm(context)
    }

    // A short widget hides the week.
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        try {
            updateWidget(context, appWidgetManager, appWidgetId)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to resize widget $appWidgetId", e)
        }
    }

    private fun updateWidget(context: Context, manager: AppWidgetManager, widgetId: Int) {
        val prefs = WidgetData.prefs(context)
        val streak = WidgetData.streak(prefs)
        val ready = WidgetData.isReadyToday(prefs)
        val size = WidgetData.size(manager, widgetId, 250, 160)
        val now = System.currentTimeMillis()

        val views = RemoteViews(context.packageName, R.layout.widget_briefing)

        val date = WidgetData.shortDate()
        views.setTextViewText(R.id.widget_date, if (streak > 0) "$date · $streak-day streak" else date)

        val waiting = WaitingWidgetData.load(context, now)
        val count = waiting.people.size
        if (count > 0) {
            val oldest = WaitingWidgetData.oldestDays(waiting, now)
            val detail = when (oldest) {
                0 -> "since today"
                1 -> "oldest yesterday"
                else -> "oldest $oldest days"
            }
            views.setTextViewText(R.id.today_wait_num, "$count")
            views.setTextViewText(R.id.today_wait_text, " waiting on you · $detail")
        } else {
            views.setTextViewText(R.id.today_wait_num, "")
            views.setTextViewText(
                R.id.today_wait_text,
                if (waiting.known) "Nobody waiting on you" else "Open Echo to see who's waiting",
            )
        }

        val todos = TodoWidgetData.today(context)
        val due = todos.count { !it.done }
        when {
            due > 0 -> {
                views.setTextViewText(R.id.today_due_num, "$due")
                views.setTextViewText(R.id.today_due_text, if (due == 1) " to-do due today" else " to-dos due today")
            }
            todos.isNotEmpty() -> {
                views.setTextViewText(R.id.today_due_num, "")
                views.setTextViewText(R.id.today_due_text, "All to-dos done")
            }
            else -> {
                views.setTextViewText(R.id.today_due_num, "")
                views.setTextViewText(R.id.today_due_text, "No to-dos due today")
            }
        }

        val owesYou = WidgetData.readLongOrInt(prefs, "flutter.widget_owes_you_v1").toInt()
        if (owesYou > 0) {
            views.setTextViewText(R.id.today_owe_num, " · $owesYou")
            views.setTextViewText(R.id.today_owe_text, if (owesYou == 1) " owes you" else " owe you")
        } else {
            views.setTextViewText(R.id.today_owe_num, "")
            views.setTextViewText(R.id.today_owe_text, "")
        }

        // With the briefing off and none cached, the button has nothing to
        // play and no time to wait for.
        if (!ready && !WidgetData.briefingOn(prefs)) {
            views.setViewVisibility(R.id.widget_badge, View.GONE)
        } else if (ready) {
            views.setImageViewResource(R.id.widget_badge_icon, R.drawable.ic_widget_play)
            views.setInt(R.id.widget_badge, "setBackgroundResource", R.drawable.widget_play_badge_bg)
        } else {
            views.setImageViewResource(R.id.widget_badge_icon, R.drawable.ic_widget_clock)
            views.setInt(R.id.widget_badge, "setBackgroundResource", R.drawable.widget_clock_badge_bg)
        }

        views.setViewVisibility(R.id.today_track, if (size.heightDp < TRACK_MIN_HEIGHT_DP) View.GONE else View.VISIBLE)
        val states = WidgetData.weekStates(prefs)
        for (i in DOT_IDS.indices) {
            views.setImageViewResource(DOT_IDS[i], dotDrawable(states[i]))
        }

        views.setOnClickPendingIntent(R.id.widget_root, WidgetData.openRoute(context, WIDGET_REQUEST + widgetId * 2, WidgetData.ROUTE_TODAY))
        views.setOnClickPendingIntent(
            R.id.widget_badge,
            WidgetData.openRoute(context, WIDGET_REQUEST + widgetId * 2 + 1, WidgetData.ROUTE_TODAY, autoplay = ready),
        )
        manager.updateAppWidget(widgetId, views)
    }
}
