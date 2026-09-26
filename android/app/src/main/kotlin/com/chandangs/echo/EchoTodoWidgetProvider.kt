package com.chandangs.echo

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.text.SpannableString
import android.text.Spanned
import android.text.style.StrikethroughSpan
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * "Echo To-do": today's list, with Echo's waveform as the progress meter, the
 * next thing up featured, and pearl checkboxes you can tick right here. Also
 * handles ticks from the small progress widget.
 */
class EchoTodoWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val TAG = "EchoTodoWidget"
        const val ACTION_TOGGLE = "com.chandangs.echo.TODO_TOGGLE"
        const val EXTRA_TODO_ID = "todo_id"

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, EchoTodoWidgetProvider::class.java))
            if (ids.isNotEmpty()) EchoTodoWidgetProvider().onUpdate(context, manager, ids)
        }

        fun openApp(context: Context, requestCode: Int): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_MAIN
                addCategory(Intent.CATEGORY_LAUNCHER)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            return PendingIntent.getActivity(
                context, requestCode, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        fun toggle(context: Context, requestCode: Int, todoId: Int): PendingIntent {
            val intent = Intent(context, EchoTodoWidgetProvider::class.java).apply {
                action = ACTION_TOGGLE
                putExtra(EXTRA_TODO_ID, todoId)
            }
            return PendingIntent.getBroadcast(
                context, requestCode, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_TOGGLE) {
            val id = intent.getIntExtra(EXTRA_TODO_ID, -1)
            if (id >= 0) {
                TodoWidgetData.toggle(context, id)
                updateAll(context)
                EchoTodoOrbWidgetProvider.updateAll(context)
            }
            return
        }
        super.onReceive(context, intent)
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

    override fun onAppWidgetOptionsChanged(
        context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int, newOptions: Bundle,
    ) {
        render(context, appWidgetManager, appWidgetId)
    }

    private fun render(context: Context, manager: AppWidgetManager, widgetId: Int) {
        val views = RemoteViews(context.packageName, R.layout.widget_todo)
        val green = context.getColor(R.color.todo_widget_green)
        val text = context.getColor(R.color.todo_widget_text)
        val text2 = context.getColor(R.color.todo_widget_text2)
        val track = context.getColor(R.color.todo_widget_track)

        val now = Date()
        views.setTextViewText(R.id.todo_day, SimpleDateFormat("EEEE", Locale.getDefault()).format(now))
        views.setTextViewText(R.id.todo_date, SimpleDateFormat("d MMMM", Locale.getDefault()).format(now))
        views.setOnClickPendingIntent(R.id.todo_root, openApp(context, widgetId))

        val today = TodoWidgetData.today(context)
        val tomorrow = TodoWidgetData.tomorrow(context)
        val done = today.count { it.done }
        val total = today.size
        val allDone = total > 0 && done == total

        val widthDp = manager.getAppWidgetOptions(widgetId)
            .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 250)
            .coerceAtLeast(180) - 28
        views.setImageViewBitmap(R.id.todo_orb, TodoWidgetArt.orb(context, 30f, allDone))
        views.setImageViewBitmap(
            R.id.todo_wave,
            TodoWidgetArt.wave(context, widthDp.toFloat(), 30f, if (total == 0) 0f else done / total.toFloat(), green, track),
        )

        val rows = listOf(
            Triple(R.id.todo_row1, R.id.todo_row1_check, Pair(R.id.todo_row1_title, R.id.todo_row1_time)),
            Triple(R.id.todo_row2, R.id.todo_row2_check, Pair(R.id.todo_row2_title, R.id.todo_row2_time)),
        )

        if (!TodoWidgetData.hasList(context)) {
            views.setTextViewText(R.id.todo_count, "")
            views.setTextViewText(R.id.todo_left, "")
            views.setViewVisibility(R.id.todo_empty, View.VISIBLE)
            views.setTextViewText(
                R.id.todo_empty,
                if (WidgetData.isReadyToday(WidgetData.prefs(context)))
                    "No list yet. Open today's briefing and tap Make a to-do list at the end."
                else
                    "Your to-do list comes from today's briefing.",
            )
            views.setViewVisibility(R.id.todo_next, View.GONE)
            rows.forEach { views.setViewVisibility(it.first, View.GONE) }
            views.setTextViewText(R.id.todo_more, "")
            views.setTextViewText(R.id.todo_tomorrow, "")
            manager.updateAppWidget(widgetId, views)
            return
        }

        views.setViewVisibility(R.id.todo_empty, View.GONE)
        views.setTextViewText(R.id.todo_count, if (total == 0) "–" else "$done/$total")
        views.setTextViewText(
            R.id.todo_left,
            when {
                total == 0 -> "nothing today"
                allDone -> "done"
                else -> "${total - done} left"
            },
        )

        val next = today.firstOrNull { !it.done }
        views.setViewVisibility(R.id.todo_next, View.VISIBLE)
        when {
            next != null -> {
                views.setTextViewText(R.id.todo_next_when, TodoWidgetData.whenLabel(next))
                views.setTextViewText(R.id.todo_next_title, next.title)
                views.setViewVisibility(R.id.todo_next_check, View.VISIBLE)
                views.setImageViewBitmap(R.id.todo_next_check, TodoWidgetArt.check(context, 30f, false, green))
                views.setOnClickPendingIntent(R.id.todo_next_check, toggle(context, widgetId * 10, next.id))
            }
            allDone -> {
                val name = WidgetData.prefs(context).getString("flutter.user_name", null)
                views.setTextViewText(R.id.todo_next_when, "That's everything")
                views.setTextViewText(R.id.todo_next_title, if (name.isNullOrBlank()) "Nice work." else "Nice work, $name.")
                views.setViewVisibility(R.id.todo_next_check, View.GONE)
            }
            else -> {
                views.setTextViewText(R.id.todo_next_when, "Tomorrow")
                views.setTextViewText(R.id.todo_next_title, tomorrow.firstOrNull()?.title ?: "Nothing planned yet")
                views.setViewVisibility(R.id.todo_next_check, View.GONE)
            }
        }

        val rest = today.filter { it != next }.sortedWith(compareBy({ it.done }, { it.sort })).take(2)
        rows.forEachIndexed { i, (row, check, texts) ->
            val item = rest.getOrNull(i)
            if (item == null) {
                views.setViewVisibility(row, View.GONE)
                return@forEachIndexed
            }
            views.setViewVisibility(row, View.VISIBLE)
            val title = SpannableString(item.title)
            if (item.done) title.setSpan(StrikethroughSpan(), 0, title.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            views.setTextViewText(texts.first, title)
            views.setTextColor(texts.first, if (item.done) Color.argb(115, Color.red(text), Color.green(text), Color.blue(text)) else text)
            views.setTextViewText(texts.second, item.time ?: "")
            views.setTextColor(texts.second, text2)
            views.setImageViewBitmap(check, TodoWidgetArt.check(context, 20f, item.done, green))
            views.setOnClickPendingIntent(check, toggle(context, widgetId * 10 + i + 1, item.id))
        }

        views.setTextViewText(R.id.todo_more, if (total > 3) "+${total - 3} more today" else "")
        views.setTextViewText(R.id.todo_tomorrow, if (tomorrow.isNotEmpty()) "Tomorrow · ${tomorrow.size}" else "")

        manager.updateAppWidget(widgetId, views)
    }
}
