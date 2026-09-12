package com.example.project_echo

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.Log
import android.widget.RemoteViews

/**
 * "Today" home-screen widget: a bold streak number on a deep-green gradient
 * with a status pill (countdown → ready). A second, separate widget from the
 * Streak Card — Android has no iOS-style widget stacking, so distinct placeable
 * widgets are the equivalent.
 */
class EchoStreakWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val TAG = "EchoStreakWidget"

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
    }

    private fun updateWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
        val prefs = WidgetData.prefs(context)
        val streak = WidgetData.streak(prefs)

        val views = RemoteViews(context.packageName, R.layout.widget_streak_ring)
        views.setTextViewText(R.id.widget_today_num, streak.toString())
        views.setTextViewText(R.id.widget_today_status, WidgetData.statusText(prefs))

        val launchIntent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EchoBriefingWidgetProvider.EXTRA_AUTOPLAY, true)
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            appWidgetId,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        views.setOnClickPendingIntent(R.id.widget_today_root, pendingIntent)

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }
}
