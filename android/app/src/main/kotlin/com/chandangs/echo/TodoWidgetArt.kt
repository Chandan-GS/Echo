package com.chandangs.echo

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * Echo's visual marks for the to-do widgets, drawn as bitmaps because
 * RemoteViews can't host Flutter: the pearl orb (the mascot), the waveform
 * used as a progress meter, the pearl checkbox, and the progress halo.
 */
object TodoWidgetArt {
    private val orbColors = intArrayOf(
        Color.parseColor("#FFFFFF"),
        Color.parseColor("#F4F9F0"),
        Color.parseColor("#D9E8DB"),
        Color.parseColor("#B4D1BA"),
        Color.parseColor("#9EC0A6"),
    )
    private val orbStops = floatArrayOf(0f, 0.16f, 0.4f, 0.7f, 1f)
    private val eye = Color.parseColor("#222F27")
    private val ring = Color.parseColor("#8FE0A6")
    private val checkInk = Color.parseColor("#2F5F35")

    private fun px(context: Context, dp: Float): Int =
        (dp * context.resources.displayMetrics.density).roundToInt().coerceAtLeast(1)

    private fun drawOrb(canvas: Canvas, cx: Float, cy: Float, r: Float, happy: Boolean, withFace: Boolean) {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.shader = RadialGradient(
            cx - r * 0.28f, cy - r * 0.4f, r * 1.7f, orbColors, orbStops, Shader.TileMode.CLAMP,
        )
        canvas.drawCircle(cx, cy, r, paint)
        paint.shader = null
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = r * 0.05f
        paint.color = ring
        paint.alpha = 115
        canvas.drawCircle(cx, cy, r, paint)
        if (!withFace) return

        paint.alpha = 255
        paint.color = eye
        val ex = r * 0.3f
        if (happy) {
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = r * 0.1f
            paint.strokeCap = Paint.Cap.ROUND
            for (side in listOf(-1f, 1f)) {
                val ecx = cx + side * ex
                canvas.drawArc(RectF(ecx - r * 0.13f, cy - r * 0.1f, ecx + r * 0.13f, cy + r * 0.16f), 200f, 140f, false, paint)
            }
        } else {
            paint.style = Paint.Style.FILL
            val w = r * 0.18f
            val h = r * 0.34f
            for (side in listOf(-1f, 1f)) {
                val ecx = cx + side * ex
                canvas.drawRoundRect(RectF(ecx - w / 2, cy - h / 2 + r * 0.04f, ecx + w / 2, cy + h / 2 + r * 0.04f), w, w, paint)
            }
        }
    }

    /** The mascot on its own. */
    fun orb(context: Context, sizeDp: Float, happy: Boolean): Bitmap {
        val s = px(context, sizeDp)
        val bmp = Bitmap.createBitmap(s, s, Bitmap.Config.ARGB_8888)
        drawOrb(Canvas(bmp), s / 2f, s / 2f, s / 2f - s * 0.04f, happy, withFace = true)
        return bmp
    }

    /** Echo's waveform; bars light up green left→right as the day is done. */
    fun wave(context: Context, widthDp: Float, heightDp: Float, progress: Float, on: Int, off: Int): Bitmap {
        val w = px(context, widthDp)
        val h = px(context, heightDp)
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val bars = 34
        val gap = px(context, 3f).toFloat()
        val barW = (w - gap * (bars - 1)) / bars
        val lit = (progress * bars).roundToInt()
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        for (i in 0 until bars) {
            val x = i / (bars - 1f)
            val shape = 0.18f + 0.82f * abs(
                sin(x * PI * 2.2) * 0.6 + sin(x * PI * 5.1 + 0.8) * 0.4,
            ).toFloat() * sin(x * PI).toFloat()
            val edge = i == lit - 1
            val bh = (h * shape * (if (edge) 1.15f else 1f)).coerceIn(px(context, 3f).toFloat(), h.toFloat())
            val left = i * (barW + gap)
            paint.color = if (i < lit) on else off
            canvas.drawRoundRect(RectF(left, (h - bh) / 2, left + barW, (h + bh) / 2), barW / 2, barW / 2, paint)
        }
        return bmp
    }

    /** An empty ring, or a small pearl orb with a check when done. */
    fun check(context: Context, sizeDp: Float, done: Boolean, green: Int): Bitmap {
        val s = px(context, sizeDp)
        val bmp = Bitmap.createBitmap(s, s, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val stroke = px(context, 2f).toFloat()
        val r = s / 2f - stroke
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        if (!done) {
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = stroke
            paint.color = green
            paint.alpha = 128
            canvas.drawCircle(s / 2f, s / 2f, r, paint)
            return bmp
        }
        drawOrb(canvas, s / 2f, s / 2f, r + stroke * 0.5f, happy = false, withFace = false)
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = s * 0.1f
        paint.strokeCap = Paint.Cap.ROUND
        paint.strokeJoin = Paint.Join.ROUND
        paint.color = checkInk
        val path = Path().apply {
            moveTo(s * 0.3f, s * 0.53f)
            lineTo(s * 0.45f, s * 0.67f)
            lineTo(s * 0.71f, s * 0.36f)
        }
        canvas.drawPath(path, paint)
        return bmp
    }

    /** Echo inside a green progress ring. */
    fun halo(context: Context, sizeDp: Float, progress: Float, happy: Boolean, fill: Int, track: Int): Bitmap {
        val s = px(context, sizeDp)
        val bmp = Bitmap.createBitmap(s, s, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val stroke = px(context, 5f).toFloat()
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
        drawOrb(canvas, s / 2f, s / 2f, s * 0.32f, happy, withFace = true)
        return bmp
    }
}
