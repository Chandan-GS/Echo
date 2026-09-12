package com.example.project_echo

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.util.Log
import android.widget.RemoteViews

/**
 * "Streak Card" home-screen widget: the current streak heading, a live status
 * line (countdown → "Ready — tap to play"), a play/clock badge, and a Mon→Sun
 * day tracker showing which days were heard. Everything is computed natively
 * from stored prefs against the device clock (see [WidgetData]), so it stays
 * accurate even if the app hasn't run in days.
 */
class EchoBriefingWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val TAG = "EchoBriefingWidget"
        const val EXTRA_AUTOPLAY = "autoplay_from_widget"

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
    }

    private fun updateWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
        val prefs = WidgetData.prefs(context)
        val streak = WidgetData.streak(prefs)
        val ready = WidgetData.isReadyToday(prefs)

        val views = RemoteViews(context.packageName, R.layout.widget_briefing)

        views.setTextViewText(
            R.id.widget_streak_heading,
            if (streak > 0) "$streak Day Streak" else "Start your streak",
        )

        views.setTextViewText(R.id.widget_status, WidgetData.statusText(prefs))
        views.setTextColor(
            R.id.widget_status,
            Color.parseColor(if (ready) "#FF49884F" else "#FF1E1E1E"),
        )

        if (ready) {
            views.setImageViewResource(R.id.widget_badge_icon, R.drawable.ic_widget_play)
            views.setInt(R.id.widget_badge, "setBackgroundResource", R.drawable.widget_play_badge_bg)
        } else {
            views.setImageViewResource(R.id.widget_badge_icon, R.drawable.ic_widget_clock)
            views.setInt(R.id.widget_badge, "setBackgroundResource", R.drawable.widget_clock_badge_bg)
        }

        val states = WidgetData.weekStates(prefs)
        for (i in DOT_IDS.indices) {
            views.setImageViewResource(DOT_IDS[i], dotDrawable(states[i]))
        }

        val launchIntent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_AUTOPLAY, true)
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            appWidgetId,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }
}
