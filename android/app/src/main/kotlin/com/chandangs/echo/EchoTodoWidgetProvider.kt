package com.chandangs.echo

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.Handler
import android.os.Looper
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
 * "Echo To-do": up to four of today's to-dos, unfinished first, which can be
 * ticked right in the widget. On Android 12+ each check is a real CheckBox, so
 * the tick animates in place; the ticked item then holds its spot for a moment
 * before the list settles. Also handles ticks for the small progress widget.
 */
class EchoTodoWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val TAG = "EchoTodoWidget"
        const val ACTION_TOGGLE = "com.chandangs.echo.TODO_TOGGLE"
        const val EXTRA_TODO_ID = "todo_id"
        private const val ROWS = 4

        /** How long a just-ticked item stays in place before the list re-sorts. */
        private const val SETTLE_MS = 1100L

        /** Let the check animation start before the title strikes through. */
        private const val STRIKE_MS = 240L

        private val rowIds = arrayOf(
            intArrayOf(R.id.todo_row1, R.id.todo_row1_check, R.id.todo_row1_title, R.id.todo_row1_time, 0),
            intArrayOf(R.id.todo_row2, R.id.todo_row2_check, R.id.todo_row2_title, R.id.todo_row2_time, R.id.todo_div2),
            intArrayOf(R.id.todo_row3, R.id.todo_row3_check, R.id.todo_row3_title, R.id.todo_row3_time, R.id.todo_div3),
            intArrayOf(R.id.todo_row4, R.id.todo_row4_check, R.id.todo_row4_title, R.id.todo_row4_time, R.id.todo_div4),
        )

        fun updateAll(context: Context, pinnedId: Int = -1) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, EchoTodoWidgetProvider::class.java))
            for (id in ids) {
                try {
                    render(context, manager, id, pinnedId)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to update widget $id", e)
                }
            }
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

        private fun toggleIntent(context: Context, requestCode: Int, todoId: Int): PendingIntent {
            val intent = Intent(context, EchoTodoWidgetProvider::class.java).apply {
                action = ACTION_TOGGLE
                putExtra(EXTRA_TODO_ID, todoId)
            }
            // Mutable on 12+ so the system can add EXTRA_CHECKED from the CheckBox.
            val mutability = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                PendingIntent.FLAG_MUTABLE else PendingIntent.FLAG_IMMUTABLE
            return PendingIntent.getBroadcast(
                context, requestCode, intent, PendingIntent.FLAG_UPDATE_CURRENT or mutability,
            )
        }

        private fun render(context: Context, manager: AppWidgetManager, widgetId: Int, pinnedId: Int) {
            val views = RemoteViews(context.packageName, R.layout.widget_todo)
            val green = context.getColor(R.color.todo_widget_green)
            val text = context.getColor(R.color.todo_widget_text)
            val ring = context.getColor(R.color.todo_widget_check_ring)
            val tick = context.getColor(R.color.todo_widget_bg)
            val checkBoxes = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S

            views.setTextViewText(R.id.todo_date, SimpleDateFormat("EEE d MMM", Locale.getDefault()).format(Date()))
            views.setOnClickPendingIntent(R.id.todo_root, openApp(context, widgetId))

            val today = TodoWidgetData.today(context)
            val tomorrow = TodoWidgetData.tomorrow(context)
            val done = today.count { it.done }
            val left = today.size - done

            if (!TodoWidgetData.hasList(context)) {
                views.setTextViewText(R.id.todo_left, "")
                views.setViewVisibility(R.id.todo_empty, View.VISIBLE)
                views.setTextViewText(
                    R.id.todo_empty,
                    if (WidgetData.isReadyToday(WidgetData.prefs(context)))
                        "No list yet. Make one from today's briefing."
                    else
                        "Your to-do list comes from today's briefing.",
                )
                views.setViewVisibility(R.id.todo_list, View.GONE)
                views.setTextViewText(R.id.todo_more, "")
                views.setTextViewText(R.id.todo_tomorrow, "")
                manager.updateAppWidget(widgetId, views)
                return
            }

            views.setViewVisibility(R.id.todo_empty, View.GONE)
            views.setViewVisibility(R.id.todo_list, View.VISIBLE)
            views.setTextViewText(
                R.id.todo_left,
                when {
                    today.isEmpty() -> "Nothing today"
                    left == 0 -> "All done"
                    else -> "$left left"
                },
            )

            // Unfinished first, by time. A just-ticked item keeps its spot
            // until the settle pass, so it doesn't jump away mid-animation.
            val ordered = today.sortedWith(
                compareBy({ it.done && it.id != pinnedId }, { it.sort }),
            ).take(ROWS)

            rowIds.forEachIndexed { i, ids ->
                val (row, check, title, time, divider) = ids.toList()
                val item = ordered.getOrNull(i)
                if (divider != 0) views.setViewVisibility(divider, if (item == null) View.GONE else View.VISIBLE)
                if (item == null) {
                    views.setViewVisibility(row, View.GONE)
                    return@forEachIndexed
                }
                views.setViewVisibility(row, View.VISIBLE)
                val label = SpannableString(item.title)
                if (item.done) label.setSpan(StrikethroughSpan(), 0, label.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                views.setTextViewText(title, label)
                views.setTextColor(
                    title,
                    if (item.done) Color.argb(115, Color.red(text), Color.green(text), Color.blue(text)) else text,
                )
                views.setTextViewText(time, item.time ?: "")
                views.setTextColor(time, if (item.done) Color.argb(115, Color.red(green), Color.green(green), Color.blue(green)) else green)

                val toggle = toggleIntent(context, widgetId * 10 + i, item.id)
                if (checkBoxes) {
                    views.setCompoundButtonChecked(check, item.done)
                    views.setOnCheckedChangeResponse(check, RemoteViews.RemoteResponse.fromPendingIntent(toggle))
                } else {
                    views.setImageViewBitmap(check, TodoWidgetArt.check(context, 22f, item.done, green, ring, tick))
                    views.setOnClickPendingIntent(check, toggle)
                }
            }

            views.setTextViewText(R.id.todo_more, if (today.size > ROWS) "+${today.size - ROWS} more today" else "")
            views.setTextViewText(R.id.todo_tomorrow, if (tomorrow.isNotEmpty()) "Tomorrow · ${tomorrow.size}" else "")
            manager.updateAppWidget(widgetId, views)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_TOGGLE) {
            super.onReceive(context, intent)
            return
        }
        val id = intent.getIntExtra(EXTRA_TODO_ID, -1)
        if (id < 0) return
        val checked = if (intent.hasExtra(RemoteViews.EXTRA_CHECKED))
            intent.getBooleanExtra(RemoteViews.EXTRA_CHECKED, false) else null
        TodoWidgetData.setDone(context, id, checked)

        // Strike the title once the check has started animating, keep the item
        // in place, then let the list settle. The small widget updates at once.
        val pending = goAsync()
        val handler = Handler(Looper.getMainLooper())
        EchoTodoOrbWidgetProvider.updateAll(context)
        handler.postDelayed({ updateAll(context, pinnedId = id) }, STRIKE_MS)
        handler.postDelayed({
            try {
                updateAll(context)
            } finally {
                pending.finish()
            }
        }, SETTLE_MS)
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (id in appWidgetIds) {
            try {
                render(context, appWidgetManager, id, -1)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to update widget $id", e)
            }
        }
    }
}
