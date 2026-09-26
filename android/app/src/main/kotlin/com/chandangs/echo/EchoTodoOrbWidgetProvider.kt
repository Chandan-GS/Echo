package com.chandangs.echo

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.text.style.RelativeSizeSpan
import android.util.Log
import android.widget.RemoteViews

/** "Echo To-do Progress": Echo inside a halo that fills as today's list is done. */
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
        val views = RemoteViews(context.packageName, R.layout.widget_todo_orb)
        val green = context.getColor(R.color.todo_widget_green)
        val text2 = context.getColor(R.color.todo_widget_text2)
        val track = context.getColor(R.color.todo_widget_track)
        views.setOnClickPendingIntent(R.id.orb_root, EchoTodoWidgetProvider.openApp(context, 5000 + widgetId))

        val today = TodoWidgetData.today(context)
        val tomorrow = TodoWidgetData.tomorrow(context)
        val done = today.count { it.done }
        val total = today.size
        val allDone = total > 0 && done == total

        views.setImageViewBitmap(
            R.id.orb_halo,
            TodoWidgetArt.halo(context, 96f, if (total == 0) 0f else done / total.toFloat(), allDone, green, track),
        )

        if (!TodoWidgetData.hasList(context)) {
            views.setTextViewText(R.id.orb_count, "No list yet")
            views.setTextViewText(R.id.orb_next, "Make one from your briefing")
            manager.updateAppWidget(widgetId, views)
            return
        }

        val count = SpannableStringBuilder()
        if (total == 0) {
            count.append("Nothing today")
        } else {
            count.append("$done of $total")
            val start = count.length
            count.append(" done")
            count.setSpan(RelativeSizeSpan(0.7f), start, count.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            count.setSpan(ForegroundColorSpan(text2), start, count.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
        views.setTextViewText(R.id.orb_count, count)

        val next = today.firstOrNull { !it.done }
        views.setTextViewText(
            R.id.orb_next,
            when {
                next != null -> if (next.time != null) "${next.time} · ${next.title}" else next.title
                tomorrow.isNotEmpty() -> "Tomorrow: ${tomorrow.size} to-do${if (tomorrow.size == 1) "" else "s"}"
                else -> "All clear"
            },
        )
        manager.updateAppWidget(widgetId, views)
    }
}
