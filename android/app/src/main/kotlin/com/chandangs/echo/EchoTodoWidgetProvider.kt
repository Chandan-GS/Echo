package com.chandangs.echo

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
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
 * "Next to-do": the next thing on today's list and when, ticked right in the
 * widget. Sized up (including placements from before this was Next to-do) it
 * shows today's list instead. On Android 12+ each check is a real CheckBox, so
 * the tick animates in place; the ticked item then holds its spot for a moment
 * before the next one moves up.
 */
class EchoTodoWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val TAG = "EchoTodoWidget"
        const val ACTION_TOGGLE = "com.chandangs.echo.TODO_TOGGLE"
        const val EXTRA_TODO_ID = "todo_id"
        private const val ROWS = 4

        /** Below this it's the one-line card; at it and above, today's list. */
        private const val LIST_MIN_HEIGHT_DP = 150

        /** Below this there's no room for the line about where it came from. */
        private const val SUB_MIN_HEIGHT_DP = 96

        /** How long a just-ticked item stays in place before the list re-sorts. */
        private const val SETTLE_MS = 1100L

        /** Let the check animation start before the title strikes through. */
        private const val STRIKE_MS = 240L

        private const val WIDGET_REQUEST = 1_000_000

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
            val size = WidgetData.size(manager, widgetId, 250, 80)
            if (size.heightDp >= LIST_MIN_HEIGHT_DP) {
                renderList(context, manager, widgetId, pinnedId)
            } else {
                renderNext(context, manager, widgetId, pinnedId, size)
            }
        }

        private fun bindCheck(views: RemoteViews, check: Int, done: Boolean, toggle: PendingIntent) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                views.setCompoundButtonChecked(check, done)
                views.setOnCheckedChangeResponse(check, RemoteViews.RemoteResponse.fromPendingIntent(toggle))
            } else {
                views.setImageViewResource(check, if (done) R.drawable.todo_check_on else R.drawable.todo_check_off)
                views.setOnClickPendingIntent(check, toggle)
            }
        }

        private fun renderNext(
            context: Context,
            manager: AppWidgetManager,
            widgetId: Int,
            pinnedId: Int,
            size: WidgetData.WidgetSize,
        ) {
            val views = RemoteViews(context.packageName, R.layout.widget_next_todo)
            views.setOnClickPendingIntent(R.id.next_root, WidgetData.openRoute(context, WIDGET_REQUEST + widgetId, WidgetData.ROUTE_TODO))

            val today = TodoWidgetData.today(context)
            val tomorrow = TodoWidgetData.tomorrow(context)
            // A just-ticked item keeps its place until the settle pass.
            val next = today.firstOrNull { !it.done || it.id == pinnedId }

            views.setViewVisibility(R.id.next_sub, View.GONE)
            views.setViewVisibility(R.id.next_done, View.GONE)
            views.setViewVisibility(R.id.next_due_box, View.VISIBLE)

            if (next != null) {
                views.setViewVisibility(R.id.next_check, View.VISIBLE)
                bindCheck(views, R.id.next_check, next.done, toggleIntent(context, widgetId * 10, next.id))
                val title = SpannableString(next.title)
                if (next.done) title.setSpan(StrikethroughSpan(), 0, title.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                views.setTextViewText(R.id.next_title, title)
                WidgetData.setColorRes(
                    context, views, R.id.next_title, "setTextColor",
                    if (next.done) R.color.todo_widget_text_done else R.color.todo_widget_text,
                )
                views.setTextViewText(R.id.next_due, TodoWidgetData.dueLabel(next) ?: "Today")
                views.setTextViewText(R.id.next_due_small, TodoWidgetData.countdown(next) ?: "")
                if (size.heightDp >= SUB_MIN_HEIGHT_DP && next.app.isNotBlank()) {
                    views.setTextViewText(R.id.next_sub, "You said so on ${next.app}")
                    views.setViewVisibility(R.id.next_sub, View.VISIBLE)
                }
                manager.updateAppWidget(widgetId, views)
                return
            }

            views.setViewVisibility(R.id.next_check, View.GONE)
            WidgetData.setColorRes(context, views, R.id.next_title, "setTextColor", R.color.todo_widget_text)

            if (today.isEmpty() && tomorrow.isNotEmpty()) {
                val first = tomorrow.first()
                views.setTextViewText(R.id.next_title, first.title)
                views.setTextViewText(R.id.next_due, "Tomorrow")
                views.setTextViewText(R.id.next_due_small, first.time?.let { TodoWidgetData.dueLabel(first) } ?: "")
                manager.updateAppWidget(widgetId, views)
                return
            }

            views.setViewVisibility(R.id.next_due_box, View.GONE)
            when {
                !TodoWidgetData.hasList(context) -> views.setTextViewText(
                    R.id.next_title,
                    if (WidgetData.isReadyToday(WidgetData.prefs(context)))
                        "Make a list from today's briefing"
                    else
                        "Comes from today's briefing",
                )
                today.isEmpty() -> views.setTextViewText(R.id.next_title, "Nothing due today")
                else -> {
                    views.setTextViewText(R.id.next_title, "Nothing else due today")
                    views.setViewVisibility(R.id.next_done, View.VISIBLE)
                }
            }
            manager.updateAppWidget(widgetId, views)
        }

        /** Today's list, for a widget with room for it. */
        private fun renderList(context: Context, manager: AppWidgetManager, widgetId: Int, pinnedId: Int) {
            val views = RemoteViews(context.packageName, R.layout.widget_todo)

            views.setTextViewText(R.id.todo_date, SimpleDateFormat("EEE d MMM", Locale.getDefault()).format(Date()))
            views.setOnClickPendingIntent(R.id.todo_root, WidgetData.openRoute(context, WIDGET_REQUEST + widgetId, WidgetData.ROUTE_TODO))

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
                views.setViewVisibility(R.id.todo_done, View.GONE)
                views.setTextViewText(R.id.todo_more, "")
                views.setTextViewText(R.id.todo_tomorrow, "")
                manager.updateAppWidget(widgetId, views)
                return
            }

            views.setViewVisibility(R.id.todo_empty, View.GONE)

            // Everything done (and not mid-tick): one calm line instead of a
            // stack of crossed-out rows.
            if (today.isNotEmpty() && left == 0 && pinnedId == -1) {
                views.setTextViewText(R.id.todo_left, "All done")
                views.setViewVisibility(R.id.todo_list, View.GONE)
                views.setViewVisibility(R.id.todo_done, View.VISIBLE)
                views.setImageViewResource(R.id.todo_done_badge, R.drawable.todo_check_on)
                views.setTextViewText(R.id.todo_done_sub, "${today.size} done")
                views.setTextViewText(R.id.todo_more, "")
                views.setTextViewText(R.id.todo_tomorrow, if (tomorrow.isNotEmpty()) "Tomorrow · ${tomorrow.size}" else "")
                manager.updateAppWidget(widgetId, views)
                return
            }
            views.setViewVisibility(R.id.todo_done, View.GONE)
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
                WidgetData.setColorRes(context, views, title, "setTextColor", if (item.done) R.color.todo_widget_text_done else R.color.todo_widget_text)
                views.setTextViewText(time, item.time ?: "")
                WidgetData.setColorRes(context, views, time, "setTextColor", if (item.done) R.color.todo_widget_green_done else R.color.todo_widget_green)

                bindCheck(views, check, item.done, toggleIntent(context, widgetId * 10 + i, item.id))
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
        // The Today widget's count moves at once; the tick is still animating here.
        EchoBriefingWidgetProvider.updateAll(context)
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
        WidgetClock.arm(context)
    }

    // Resizing can swap the card for the list and back.
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        try {
            render(context, appWidgetManager, appWidgetId, -1)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to resize widget $appWidgetId", e)
        }
    }
}
