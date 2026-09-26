package com.chandangs.echo

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.util.Log
import android.widget.RemoteViews

/** "Echo To-do Progress": a ring that fills as today's list is done, and what's next. */
class EchoTodoOrbWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val TAG = "EchoTodoOrbWidget"

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, EchoTodoOrbWidgetProvider::class.java))
            if (ids.isNotEmpty()) EchoTodoOrbWidgetProvider().onUpdate(context, manager, ids)
        }
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (id in appWidgetIds) {
            try {
                render(context, appWidgetManager, id)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to update widget $id", e)
            }
        }
    }

    private fun render(context: Context, manager: AppWidgetManager, widgetId: Int) {
        // All colours live in the layout / drawables as resources, so the
        // launcher resolves them in the current light / dark mode.
        val views = RemoteViews(context.packageName, R.layout.widget_todo_orb)
        views.setOnClickPendingIntent(R.id.orb_root, EchoTodoWidgetProvider.openApp(context, 5000 + widgetId))

        val today = TodoWidgetData.today(context)
        val tomorrow = TodoWidgetData.tomorrow(context)
        val done = today.count { it.done }
        val total = today.size
        val left = total - done
        views.setProgressBar(R.id.orb_ring, 100, if (total == 0) 0 else done * 100 / total, false)

        if (!TodoWidgetData.hasList(context)) {
            views.setTextViewText(R.id.orb_count, "")
            views.setTextViewText(R.id.orb_total, "")
            views.setTextViewText(
                R.id.orb_label,
                if (WidgetData.isReadyToday(WidgetData.prefs(context))) "No list yet" else "Briefing first",
            )
            views.setTextViewText(R.id.orb_next_time, "")
            views.setTextViewText(R.id.orb_next, "")
            manager.updateAppWidget(widgetId, views)
            return
        }

        views.setTextViewText(R.id.orb_count, if (total == 0) "" else "$done")
        views.setTextViewText(R.id.orb_total, if (total == 0) "" else "/$total")
        views.setTextViewText(
            R.id.orb_label,
            when {
                total == 0 -> "Nothing today"
                left == 0 -> "All done today"
                else -> "$left left today"
            },
        )

        val next = today.sortedBy { it.sort }.firstOrNull { !it.done }
        views.setTextViewText(R.id.orb_next_time, if (next?.time != null) "${next.time} · " else "")
        views.setTextViewText(
            R.id.orb_next,
            when {
                next != null -> next.title
                tomorrow.isNotEmpty() -> "Tomorrow: ${tomorrow.size} to-do${if (tomorrow.size == 1) "" else "s"}"
                else -> ""
            },
        )
        manager.updateAppWidget(widgetId, views)
    }
}
