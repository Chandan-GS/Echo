package com.chandangs.echo

import android.content.Context
import org.json.JSONObject

/**
 * When each chat was last opened or read, for Dart's OpenedChats: thread id
 * to epoch millis, in Flutter's shared prefs so it's there however long the
 * app has been closed.
 */
object OpenedChats {
    private const val KEY = "flutter.echo_opened_chats_v1"
    private const val MAX_THREADS = 500

    @Synchronized
    fun record(context: Context, thread: String, at: Long) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val all = try {
            JSONObject(prefs.getString(KEY, null) ?: "{}")
        } catch (e: Exception) {
            JSONObject()
        }
        all.put(thread, at)
        if (all.length() > MAX_THREADS) {
            all.keys().asSequence().toList()
                .sortedBy { all.optLong(it) }
                .take(all.length() - MAX_THREADS)
                .forEach { all.remove(it) }
        }
        prefs.edit().putString(KEY, all.toString()).apply()
    }
}
