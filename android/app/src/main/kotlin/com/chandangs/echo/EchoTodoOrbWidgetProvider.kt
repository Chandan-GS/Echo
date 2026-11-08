package com.chandangs.echo

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.os.Bundle
import android.util.Log
import android.view.View
import android.widget.RemoteViews

/**
 * "Waiting on you": the faces of the people waiting on a reply, oldest first,
 * each ringed by how long. Faces are initials on tinted discs rather than
 * photos, to stay well inside Android's widget bitmap limit. (The class keeps
 * its old name so widgets already on home screens carry on working.)
 */
class EchoTodoOrbWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val TAG = "EchoWaitingWidget"
        private const val WIDGET_REQUEST = 2_000_000

        /** Rings are thin, so a small bitmap stays sharp at any density. */
        private const val RING_MAX_PX = 96
        private const val RING_DP = 52

        /** Fewer faces when it's narrow: each needs about this much room. */
        private const val FACE_WIDTH_DP = 62

        /** Below this height the title row goes, leaving just the faces. */
        private const val HEADER_MIN_HEIGHT_DP = 100

        private val faceIds = arrayOf(
            intArrayOf(R.id.wait_face0, R.id.wait_face0_ring, R.id.wait_face0_disc, R.id.wait_face0_initial, R.id.wait_face0_name, R.id.wait_face0_age),
            intArrayOf(R.id.wait_face1, R.id.wait_face1_ring, R.id.wait_face1_disc, R.id.wait_face1_initial, R.id.wait_face1_name, R.id.wait_face1_age),
            intArrayOf(R.id.wait_face2, R.id.wait_face2_ring, R.id.wait_face2_disc, R.id.wait_face2_initial, R.id.wait_face2_name, R.id.wait_face2_age),
            intArrayOf(R.id.wait_face3, R.id.wait_face3_ring, R.id.wait_face3_disc, R.id.wait_face3_initial, R.id.wait_face3_name, R.id.wait_face3_age),
        )

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, EchoTodoOrbWidgetProvider::class.java))
            if (ids.isNotEmpty()) EchoTodoOrbWidgetProvider().onUpdate(context, manager, ids)
        }

        /** The ring as a white mask, tinted in the layout so it follows dark mode. */
        private fun ring(context: Context, progress: Float): Bitmap {
            val density = context.resources.displayMetrics.density
            val px = (RING_DP * density).toInt().coerceAtMost(RING_MAX_PX).coerceAtLeast(24)
            val bitmap = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888)
            val stroke = px * (2.5f / RING_DP)
            val inset = stroke / 2
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.WHITE
                style = Paint.Style.STROKE
                strokeWidth = stroke
                strokeCap = Paint.Cap.ROUND
            }
            Canvas(bitmap).drawArc(RectF(inset, inset, px - inset, px - inset), -90f, 360f * progress, false, paint)
            return bitmap
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
        WidgetClock.arm(context)
    }

    // A resized widget fits a different number of faces.
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        try {
            render(context, appWidgetManager, appWidgetId)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to resize widget $appWidgetId", e)
        }
    }

    private fun render(context: Context, manager: AppWidgetManager, widgetId: Int) {
        val views = RemoteViews(context.packageName, R.layout.widget_waiting)
        views.setOnClickPendingIntent(R.id.wait_root, WidgetData.openRoute(context, WIDGET_REQUEST + widgetId * 8, WidgetData.ROUTE_TODAY))

        val size = WidgetData.size(manager, widgetId, 250, 130)
        val now = System.currentTimeMillis()
        val waiting = WaitingWidgetData.load(context, now)
        val people = waiting.people
        val maxFaces = ((size.widthDp - 30) / FACE_WIDTH_DP).coerceIn(2, faceIds.size)
        val narrow = size.widthDp < 200

        views.setViewVisibility(R.id.wait_header, if (size.heightDp < HEADER_MIN_HEIGHT_DP) View.GONE else View.VISIBLE)

        if (people.isEmpty()) {
            views.setViewVisibility(R.id.wait_faces, View.GONE)
            views.setViewVisibility(R.id.wait_empty, View.VISIBLE)
            val listening = WidgetData.listening(context)
            views.setTextViewText(R.id.wait_count, if (listening && waiting.known) "All clear" else "")
            views.setViewVisibility(R.id.wait_empty_icon, if (listening && waiting.known) View.VISIBLE else View.GONE)
            views.setTextViewText(
                R.id.wait_empty_text,
                when {
                    !listening -> "Let Echo read your notifications to see who's waiting."
                    !waiting.known -> "Open Echo once and the people waiting on you will show here."
                    else -> "Nobody's waiting. You've answered everyone."
                },
            )
            manager.updateAppWidget(widgetId, views)
            return
        }

        views.setViewVisibility(R.id.wait_empty, View.GONE)
        views.setViewVisibility(R.id.wait_faces, View.VISIBLE)
        views.setTextViewText(R.id.wait_count, if (narrow) "${people.size}" else "${people.size} waiting")

        faceIds.forEachIndexed { i, ids ->
            val person = people.getOrNull(i)
            if (person == null || i >= maxFaces) {
                views.setViewVisibility(ids[0], View.GONE)
                return@forEachIndexed
            }
            views.setViewVisibility(ids[0], View.VISIBLE)
            views.setImageViewBitmap(ids[1], ring(context, WaitingWidgetData.ageProgress(person.since, now)))
            WidgetData.setColorRes(context, views, ids[1], "setColorFilter", ageColor(WaitingWidgetData.ageBand(person.since, now)))
            views.setInt(ids[2], "setColorFilter", WaitingWidgetData.tintFor(person.name))
            views.setTextViewText(ids[3], WaitingWidgetData.initial(person.name))
            views.setTextViewText(ids[4], WaitingWidgetData.shortName(person))
            views.setTextViewText(ids[5], WaitingWidgetData.shortSince(person.since, now))
            WidgetData.setColorRes(context, views, ids[5], "setTextColor", ageColor(WaitingWidgetData.ageBand(person.since, now)))
            views.setOnClickPendingIntent(
                ids[0],
                WidgetData.openRoute(context, WIDGET_REQUEST + widgetId * 8 + i + 1, WidgetData.ROUTE_PERSON, person.sender, person.source),
            )
        }
        manager.updateAppWidget(widgetId, views)
    }

    private fun ageColor(band: Int): Int = when (band) {
        0 -> R.color.widget_age_fresh
        1 -> R.color.widget_age_yesterday
        else -> R.color.widget_age_old
    }
}
