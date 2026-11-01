package com.chandangs.echo_native

import android.content.Context
import android.util.Log
import org.json.JSONArray
import java.io.File

/**
 * Notifications captured while no Flutter UI is listening, kept in a
 * [BufferStore] in the app's private files until Dart has saved them. Every
 * call shares one lock, so a notification that arrives mid-drain, or the
 * briefing alarm draining while the app does, can't lose or repeat one.
 */
object NotificationBuffer {
    private const val FILE_NAME = "echo_notification_buffer.jsonl"

    // Where the buffer used to be: one JSON array, rewritten on every append.
    private const val PREFS_NAME = "echo_notification_prefs"
    private const val BUFFER_KEY = "notification_buffer"

    private var store: BufferStore? = null

    @Synchronized
    fun append(context: Context, json: String) {
        try {
            store(context).append(json, System.currentTimeMillis())
        } catch (e: Exception) {
            Log.e("EchoNotification", "Couldn't buffer a notification", e)
        }
    }

    /**
     * Lends Dart up to [limit] of the oldest notifications, as their keys
     * and their JSON. They stay buffered until [ack]ed.
     */
    @Synchronized
    fun peek(context: Context, limit: Int): Map<String, List<String>> {
        val entries = store(context).peek(limit, System.currentTimeMillis())
        return mapOf(
            "keys" to entries.map { it.key },
            "items" to entries.map { it.json },
        )
    }

    /** Deletes the notifications Dart has saved. */
    @Synchronized
    fun ack(context: Context, keys: List<String>) {
        store(context).ack(keys)
    }

    private fun store(context: Context): BufferStore =
        store ?: BufferStore(File(context.filesDir, FILE_NAME)).also {
            migrate(context, it)
            store = it
        }

    /**
     * Moves a buffer left in SharedPreferences by an older version into the
     * file. Its keys are derived from position and content, so if the app is
     * killed before the old buffer is cleared, moving it again repeats the
     * same keys and Dart saves each notification once.
     */
    private fun migrate(context: Context, store: BufferStore) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val old = prefs.getString(BUFFER_KEY, null) ?: return
        val now = System.currentTimeMillis()
        val array = try {
            JSONArray(old)
        } catch (e: Exception) {
            Log.e("EchoNotification", "Corrupt old buffer, dropping it", e)
            JSONArray()
        }
        val entries = (0 until array.length()).mapNotNull { i ->
            val item = array.optJSONObject(i) ?: return@mapNotNull null
            val json = item.toString()
            BufferStore.Entry(
                key = "legacy-$i-${json.hashCode()}",
                capturedAt = item.optLong("timestamp", now),
                json = json,
            )
        }
        // If this throws, the old buffer stays for the next try.
        store.appendAll(entries, now)
        prefs.edit().remove(BUFFER_KEY).commit()
        if (entries.isNotEmpty()) {
            Log.i("EchoNotification", "Moved ${entries.size} buffered notifications to $FILE_NAME")
        }
    }
}
