package com.chandangs.echo

import android.content.Context
import android.util.Log
import org.json.JSONArray
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * The to-do list as the widgets see it: the JSON the Dart side stores under
 * `todo_items_v1` in FlutterSharedPreferences (see todo_item.dart for the
 * field names). "Today" is always the device's current date, so tomorrow's
 * items move up on their own at midnight even if the app hasn't run.
 */
object TodoWidgetData {
    private const val ITEMS_KEY = "flutter.todo_items_v1"
    private const val META_KEY = "flutter.todo_meta_v1"

    data class Todo(
        val id: Int,
        val title: String,
        val day: String,
        val time: String?,
        val sort: Int,
        val done: Boolean,
    )

    private fun dayKey(offsetDays: Int): String {
        val cal = Calendar.getInstance()
        cal.add(Calendar.DAY_OF_YEAR, offsetDays)
        return SimpleDateFormat("yyyy-MM-dd", Locale.US).format(cal.time)
    }

    fun all(context: Context): List<Todo> {
        val raw = WidgetData.prefs(context).getString(ITEMS_KEY, null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).map { i ->
                val o = array.getJSONObject(i)
                Todo(
                    id = o.getInt("id"),
                    title = o.optString("title"),
                    day = o.optString("day"),
                    time = if (o.isNull("time")) null else o.optString("time"),
                    sort = o.optInt("sort", 24 * 60),
                    done = o.optBoolean("done", false),
                )
            }
        } catch (e: Exception) {
            Log.e("EchoTodoWidget", "Unreadable to-do list", e)
            emptyList()
        }
    }

    fun today(context: Context): List<Todo> =
        all(context).filter { it.day == dayKey(0) }.sortedBy { it.sort }

    fun tomorrow(context: Context): List<Todo> =
        all(context).filter { it.day == dayKey(1) }.sortedBy { it.sort }

    /** Mirrors TodoState.hasList: anything for today/tomorrow, or a list made today. */
    fun hasList(context: Context): Boolean {
        if (today(context).isNotEmpty() || tomorrow(context).isNotEmpty()) return true
        val meta = WidgetData.prefs(context).getString(META_KEY, null) ?: return false
        return try {
            val madeAt = org.json.JSONObject(meta).optLong("madeAt", 0L)
            madeAt > 0 && SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(madeAt)) == dayKey(0)
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Marks an item done or not. [done] is the CheckBox's new state on Android
     * 12+; null (older versions) flips it. The app picks the change up when it
     * resumes.
     */
    @Synchronized
    fun setDone(context: Context, id: Int, done: Boolean?) {
        val prefs = WidgetData.prefs(context)
        val raw = prefs.getString(ITEMS_KEY, null) ?: return
        try {
            val array = JSONArray(raw)
            for (i in 0 until array.length()) {
                val o = array.getJSONObject(i)
                if (o.getInt("id") == id) {
                    o.put("done", done ?: !o.optBoolean("done", false))
                    break
                }
            }
            prefs.edit().putString(ITEMS_KEY, array.toString()).commit()
        } catch (e: Exception) {
            Log.e("EchoTodoWidget", "Couldn't update to-do $id", e)
        }
    }
}
