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
 * "Echo": just the pearl, with how many people are waiting. Tap to open Today.
 * (The class keeps its old name so widgets already on home screens carry on.)
 */
class EchoStreakWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val TAG = "EchoOrbWidget"
        private const val WIDGET_REQUEST = 3_000_000

        /** Under this the pearl gets the small layout, without its label. */
        private const val LARGE_MIN_SIZE_DP = 96

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, EchoStreakWidgetProvider::class.java)
            )
            if (ids.isNotEmpty()) {
                EchoStreakWidgetProvider().onUpdate(context, manager, ids)
            }
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

    // Resized: the pearl has its small and large layouts.
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
        val size = WidgetData.size(manager, widgetId, 72, 72)
        val large = size.widthDp >= LARGE_MIN_SIZE_DP && size.heightDp >= LARGE_MIN_SIZE_DP
        val views = RemoteViews(context.packageName, if (large) R.layout.widget_orb else R.layout.widget_orb_small)

        val waiting = WaitingWidgetData.load(context)
        val now = System.currentTimeMillis()
        val count = waiting.people.size
        if (count > 0) {
            val oldest = waiting.people.minOf { it.since }
            views.setViewVisibility(R.id.orb_badge, View.VISIBLE)
            views.setTextViewText(R.id.orb_badge, if (count > 99) "99+" else "$count")
            views.setInt(
                R.id.orb_badge, "setBackgroundResource",
                when (WaitingWidgetData.ageBand(oldest, now)) {
                    0 -> R.drawable.widget_orb_badge_0
                    1 -> R.drawable.widget_orb_badge_1
                    else -> R.drawable.widget_orb_badge_2
                },
            )
        } else {
            views.setViewVisibility(R.id.orb_badge, View.GONE)
        }

        views.setOnClickPendingIntent(
            R.id.orb_root,
            WidgetData.openRoute(context, WIDGET_REQUEST + widgetId, WidgetData.ROUTE_TODAY),
        )
        manager.updateAppWidget(widgetId, views)
    }
}
