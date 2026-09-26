package com.chandangs.echo_native

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/**
 * Notifications captured while no Flutter UI is listening, persisted until
 * Dart drains them. Append and drain share one lock, so a notification that
 * arrives mid-drain is never lost between the read and the clear.
 */
object NotificationBuffer {
    private const val PREFS_NAME = "echo_notification_prefs"
    private const val BUFFER_KEY = "notification_buffer"

    @Synchronized
    fun append(context: Context, json: String) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val array = try {
            JSONArray(prefs.getString(BUFFER_KEY, "[]"))
        } catch (e: Exception) {
            Log.e("EchoNotification", "Corrupt buffer, starting fresh", e)
            JSONArray()
        }
        array.put(JSONObject(json))
        prefs.edit().putString(BUFFER_KEY, array.toString()).commit()
    }

    /** Returns every buffered notification as a JSON array and clears the buffer. */
    @Synchronized
    fun drain(context: Context): String {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val buffered = prefs.getString(BUFFER_KEY, "[]") ?: "[]"
        prefs.edit().putString(BUFFER_KEY, "[]").commit()
        return buffered
    }
}
