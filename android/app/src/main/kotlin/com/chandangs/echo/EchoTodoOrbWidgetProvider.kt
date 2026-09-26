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
        val views = RemoteViews(context.packageName, R.layout.widget_todo_orb)
        val green = context.getColor(R.color.todo_widget_green)
        val text2 = context.getColor(R.color.todo_widget_text2)
        val track = context.getColor(R.color.todo_widget_track)
        views.setOnClickPendingIntent(R.id.orb_root, EchoTodoWidgetProvider.openApp(context, 5000 + widgetId))

        val today = TodoWidgetData.today(context)
        val tomorrow = TodoWidgetData.tomorrow(context)
        val done = today.count { it.done }
        val total = today.size
        val left = total - done

        views.setImageViewBitmap(
            R.id.orb_ring,
            TodoWidgetArt.ring(context, 92f, if (total == 0) 0f else done / total.toFloat(), green, track),
        )

        if (!TodoWidgetData.hasList(context)) {
            views.setTextViewText(R.id.orb_count, "")
            views.setTextViewText(
                R.id.orb_label,
                if (WidgetData.isReadyToday(WidgetData.prefs(context))) "No list yet" else "Briefing first",
            )
            views.setTextViewText(R.id.orb_next, "")
            manager.updateAppWidget(widgetId, views)
            return
        }

        val count = SpannableStringBuilder("$done")
        if (total > 0) {
            val start = count.length
            count.append("/$total")
            count.setSpan(RelativeSizeSpan(0.58f), start, count.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            count.setSpan(ForegroundColorSpan(text2), start, count.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
        views.setTextViewText(R.id.orb_count, if (total == 0) "" else count)
        views.setTextViewText(
            R.id.orb_label,
            when {
                total == 0 -> "Nothing today"
                left == 0 -> "All done today"
                else -> "$left left today"
            },
        )

        val next = today.sortedBy { it.sort }.firstOrNull { !it.done }
        val nextText = SpannableStringBuilder()
        when {
            next != null -> {
                if (next.time != null) {
                    nextText.append(next.time)
                    nextText.setSpan(ForegroundColorSpan(green), 0, nextText.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                    nextText.append(" · ")
                }
                nextText.append(next.title)
            }
            tomorrow.isNotEmpty() -> nextText.append("Tomorrow: ${tomorrow.size} to-do${if (tomorrow.size == 1) "" else "s"}")
        }
        views.setTextViewText(R.id.orb_next, nextText)
        manager.updateAppWidget(widgetId, views)
    }
}
