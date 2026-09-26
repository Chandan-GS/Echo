package com.chandangs.echo

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import kotlin.math.roundToInt

/**
 * Bitmaps for the to-do widgets: the progress ring, and the check used on
 * Android versions before 12 (from 12 on, the widget hosts a real animated
 * CheckBox instead — see drawable/todo_check.xml).
 */
object TodoWidgetArt {
    private fun px(context: Context, dp: Float): Int =
        (dp * context.resources.displayMetrics.density).roundToInt().coerceAtLeast(1)

    /** An empty ring, or a filled green circle with a tick — like the app's check. */
    fun check(context: Context, sizeDp: Float, done: Boolean, green: Int, ring: Int, tick: Int): Bitmap {
        val s = px(context, sizeDp)
        val bmp = Bitmap.createBitmap(s, s, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val stroke = px(context, 2f).toFloat()
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        if (!done) {
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = stroke
            paint.color = ring
            canvas.drawCircle(s / 2f, s / 2f, s / 2f - stroke, paint)
            return bmp
        }
        paint.color = green
        canvas.drawCircle(s / 2f, s / 2f, s / 2f - stroke / 2, paint)
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = s * 0.1f
        paint.strokeCap = Paint.Cap.ROUND
        paint.strokeJoin = Paint.Join.ROUND
        paint.color = tick
        canvas.drawPath(
            Path().apply {
                moveTo(s * 0.3f, s * 0.52f)
                lineTo(s * 0.43f, s * 0.64f)
                lineTo(s * 0.7f, s * 0.37f)
            },
            paint,
        )
        return bmp
    }

    /** A progress ring; the count sits on top of it as text. */
    fun ring(context: Context, sizeDp: Float, progress: Float, fill: Int, track: Int): Bitmap {
        val s = px(context, sizeDp)
        val bmp = Bitmap.createBitmap(s, s, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val stroke = px(context, 6f).toFloat()
        val rect = RectF(stroke / 2, stroke / 2, s - stroke / 2, s - stroke / 2)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = stroke
            strokeCap = Paint.Cap.ROUND
        }
        paint.color = track
        canvas.drawArc(rect, 0f, 360f, false, paint)
        if (progress > 0f) {
            paint.color = fill
            canvas.drawArc(rect, -90f, 360f * progress.coerceIn(0f, 1f), false, paint)
        }
        return bmp
    }
}
