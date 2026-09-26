package com.chandangs.echo_native

import android.Manifest
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.provider.CalendarContract
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

object CalendarEvents {
    /**
     * Calendar event occurrences starting in [startMs, endMs], as a JSON array
     * of {source, sender, content, timestamp}. Queries Instances rather than
     * Events so recurring events (a daily standup) yield one row per
     * occurrence. Returns "[]" without calendar permission.
     */
    fun query(context: Context, startMs: Long, endMs: Long): String {
        if (context.checkSelfPermission(Manifest.permission.READ_CALENDAR) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return "[]"
        }

        val uri = CalendarContract.Instances.CONTENT_URI.buildUpon().also {
            ContentUris.appendId(it, startMs)
            ContentUris.appendId(it, endMs)
        }.build()
        val projection = arrayOf(
            CalendarContract.Instances.TITLE,
            CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.END,
            CalendarContract.Instances.DESCRIPTION,
            CalendarContract.Instances.ALL_DAY,
        )

        val cursor = try {
            context.contentResolver.query(
                uri, projection, null, null, "${CalendarContract.Instances.BEGIN} ASC"
            )
        } catch (e: Exception) {
            null
        }

        // Locale.US keeps "5:00 PM" parseable by the Dart relevance parser
        // regardless of the device language.
        val timeFormat = SimpleDateFormat("h:mm a", Locale.US)
        val array = JSONArray()
        cursor?.use {
            while (it.moveToNext()) {
                val title = it.getString(0)
                if (title.isNullOrEmpty()) continue
                var begin = it.getLong(1)
                val end = it.getLong(2)
                val description = it.getString(3)
                val allDay = it.getInt(4) == 1

                val times = if (allDay) {
                    // All-day instances are stored at UTC midnight; move to local
                    // midnight of the same date so the day doesn't shift.
                    begin = utcMidnightToLocal(begin)
                    "All day"
                } else {
                    "${timeFormat.format(Date(begin))} - ${timeFormat.format(Date(end))}"
                }
                val content = if (description.isNullOrEmpty()) times else "$times\n$description"

                array.put(
                    JSONObject()
                        .put("source", "Calendar")
                        .put("sender", title)
                        .put("content", content)
                        .put("timestamp", begin)
                )
            }
        }
        return array.toString()
    }

    private fun utcMidnightToLocal(utcMs: Long): Long {
        val utc = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply { timeInMillis = utcMs }
        return Calendar.getInstance().apply {
            clear()
            set(utc.get(Calendar.YEAR), utc.get(Calendar.MONTH), utc.get(Calendar.DAY_OF_MONTH))
        }.timeInMillis
    }
}
