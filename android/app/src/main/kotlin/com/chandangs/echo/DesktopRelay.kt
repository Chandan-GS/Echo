package com.chandangs.echo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Does on the phone what the owner did on their paired computer: replies,
 * to-do changes and reminders (see phone_actions.dart). Runs inside the
 * notification listener, which Android keeps alive, so it works with Echo
 * closed. Every 20 seconds, and only once a computer is paired, it asks the
 * computer for anything new, does it, and says how it went.
 *
 * A reply goes out through the chat notification's own Reply button when
 * that's still there. Otherwise the phone shows "Reply ready": Android won't
 * let an app open WhatsApp from the background, so the owner taps it to
 * open the chat with the reply typed.
 */
class DesktopRelay(private val context: Context) {
    private val thread = HandlerThread("echo-desktop-relay").apply { start() }
    private val handler = Handler(thread.looper)
    private val poll = object : Runnable {
        override fun run() {
            try {
                tick()
            } catch (e: Exception) {
                Log.d(TAG, "Couldn't reach the computer: ${e.message}")
            }
            handler.postDelayed(this, INTERVAL_MS)
        }
    }

    fun start() {
        handler.removeCallbacks(poll)
        handler.postDelayed(poll, 3_000L)
    }

    fun stop() {
        handler.removeCallbacksAndMessages(null)
        thread.quitSafely()
    }

    private fun tick() {
        val prefs = WidgetData.prefs(context)
        if (!prefs.getBoolean("flutter.prefer_desktop_engine", false)) return
        val host = prefs.getString("flutter.desktop_engine_host", null) ?: return
        val token = prefs.getString("flutter.desktop_engine_token", null)

        val actions = JSONArray(request("http://$host/actions", "GET", token, null) ?: return)
        if (actions.length() == 0) return
        val done = doneIds()
        val results = JSONArray()
        for (i in 0 until actions.length()) {
            val a = actions.optJSONObject(i) ?: continue
            val id = a.optString("id")
            // Done already, but the report was lost: just say so again.
            val outcome = if (done.has(id)) done.getString(id) else run(a).also { done.put(id, it) }
            results.put(JSONObject().put("id", id).put("ok", outcome != "failed").put("outcome", outcome))
        }
        saveDone(done)
        request("http://$host/actions/done", "POST", token, results.toString())
    }

    /** Does one action; returns how it went. */
    private fun run(a: JSONObject): String = try {
        when (a.optString("kind")) {
            "reply" -> reply(a.getString("thread"), a.getString("text"), a.optString("to"))
            "todo_done" -> {
                TodoWidgetData.setDone(context, a.getInt("id"), a.optBoolean("done", true))
                refreshWidgets()
                "done"
            }
            "todo_move" -> editTodos { items ->
                for (j in 0 until items.length()) {
                    val o = items.getJSONObject(j)
                    if (o.getInt("id") == a.getInt("id")) o.put("day", a.getString("day"))
                }
                items
            }
            "todo_delete" -> editTodos { items ->
                val kept = JSONArray()
                for (j in 0 until items.length()) {
                    val o = items.getJSONObject(j)
                    if (o.getInt("id") != a.getInt("id")) kept.put(o)
                }
                kept
            }
            "todo_add" -> addTodo(a.getJSONObject("item"))
            "remind" -> {
                remind(a)
                "done"
            }
            "unremind" -> {
                unremind(a.getString("key"))
                "done"
            }
            else -> "failed"
        }
    } catch (e: Exception) {
        Log.w(TAG, "Couldn't do ${a.optString("kind")}: ${e.message}")
        "failed"
    }

    private fun reply(thread: String, text: String, to: String): String {
        if (ReplyActions.send(context, thread, text)) return "sent"
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL, "From your computer", NotificationManager.IMPORTANCE_HIGH)
                .apply { description = "Replies written on your computer, ready to send" },
        )
        val id = REPLY_NOTIFICATION + (thread.hashCode() and 0xffff)
        val open = PendingIntent.getActivity(
            context,
            id,
            ReplyActions.writeIntent(context, thread, text),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        manager.notify(
            id,
            Notification.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(if (to.isEmpty()) "Your reply is ready" else "Your reply to $to is ready")
                .setContentText("Tap to open the chat with it typed: “$text”")
                .setStyle(Notification.BigTextStyle().bigText("Tap to open the chat with it typed: “$text”"))
                .setContentIntent(open)
                .setAutoCancel(true)
                .build(),
        )
        return "ready"
    }

    private fun editTodos(change: (JSONArray) -> JSONArray): String {
        val prefs = WidgetData.prefs(context)
        val items = JSONArray(prefs.getString(TODO_ITEMS, null) ?: "[]")
        prefs.edit().putString(TODO_ITEMS, change(items).toString()).commit()
        refreshWidgets()
        return "done"
    }

    /** Adds [item], with the next free id if the computer's guess is taken. */
    private fun addTodo(item: JSONObject): String {
        val prefs = WidgetData.prefs(context)
        val items = JSONArray(prefs.getString(TODO_ITEMS, null) ?: "[]")
        val meta = JSONObject(prefs.getString(TODO_META, null) ?: "{}")
        val ids = (0 until items.length()).map { items.getJSONObject(it).optInt("id") }.toSet()
        if ((0 until items.length()).any { items.getJSONObject(it).optString("key") == item.optString("key") }) {
            return "done"
        }
        var next = maxOf(meta.optInt("nextId", 1), (ids.maxOrNull() ?: 0) + 1)
        if (item.optInt("id") in ids || item.optInt("id") <= 0) item.put("id", next)
        next = maxOf(next, item.getInt("id") + 1)
        items.put(item)
        meta.put("nextId", next)
        prefs.edit().putString(TODO_ITEMS, items.toString()).putString(TODO_META, meta.toString()).commit()
        refreshWidgets()
        return "done"
    }

    private fun remind(a: JSONObject) {
        val prefs = WidgetData.prefs(context)
        val store = JSONObject(prefs.getString(REMINDERS, null) ?: "{}")
        val key = a.getString("key")
        val used = store.keys().asSequence().mapNotNull { store.optJSONObject(it)?.optInt("id") }.toSet()
        val id = store.optJSONObject(key)?.optInt("id")?.takeIf { it > 0 }
            ?: generateSequence(100000) { it + 1 }.first { it !in used }
        val reminder = Reminders.Reminder(
            id = id,
            key = key,
            title = a.getString("title"),
            body = a.optString("body"),
            todoId = a.optInt("todoId", -1),
            thread = if (a.isNull("thread")) null else a.optString("thread").ifEmpty { null },
        )
        val at = a.getLong("at")
        Reminders.set(context, reminder, at)
        store.put(
            key,
            JSONObject()
                .put("id", id).put("at", at)
                .put("title", reminder.title).put("body", reminder.body)
                .put("todoId", reminder.todoId.takeIf { it >= 0 } ?: JSONObject.NULL)
                .put("thread", reminder.thread ?: JSONObject.NULL),
        )
        prefs.edit().putString(REMINDERS, store.toString()).commit()
    }

    private fun unremind(key: String) {
        val prefs = WidgetData.prefs(context)
        val store = JSONObject(prefs.getString(REMINDERS, null) ?: "{}")
        store.optJSONObject(key)?.optInt("id")?.let { Reminders.cancel(context, it) }
        store.remove(key)
        prefs.edit().putString(REMINDERS, store.toString()).commit()
    }

    private fun refreshWidgets() {
        EchoTodoWidgetProvider.updateAll(context)
        EchoTodoOrbWidgetProvider.updateAll(context)
    }

    /** Ids already done, with how they went; the last hundred. */
    private fun doneIds(): JSONObject = try {
        JSONObject(context.getSharedPreferences(RELAY_PREFS, Context.MODE_PRIVATE).getString("done", "{}") ?: "{}")
    } catch (e: Exception) {
        JSONObject()
    }

    private fun saveDone(done: JSONObject) {
        while (done.length() > 100) done.remove(done.keys().next())
        context.getSharedPreferences(RELAY_PREFS, Context.MODE_PRIVATE).edit().putString("done", done.toString()).apply()
    }

    private fun request(url: String, method: String, token: String?, body: String?): String? {
        val c = URL(url).openConnection() as HttpURLConnection
        return try {
            c.requestMethod = method
            c.connectTimeout = 2_500
            c.readTimeout = 5_000
            token?.let { c.setRequestProperty("X-Echo-Token", it) }
            if (body != null) {
                c.doOutput = true
                c.setRequestProperty("Content-Type", "application/json")
                c.outputStream.use { it.write(body.toByteArray()) }
            }
            if (c.responseCode !in 200..299) null else c.inputStream.bufferedReader().use { it.readText() }
        } finally {
            c.disconnect()
        }
    }

    companion object {
        private const val TAG = "EchoDesktopRelay"
        private const val INTERVAL_MS = 20_000L
        private const val CHANNEL = "echo_desktop"
        private const val REPLY_NOTIFICATION = 300000
        private const val RELAY_PREFS = "echo_desktop_relay"
        private const val TODO_ITEMS = "flutter.todo_items_v1"
        private const val TODO_META = "flutter.todo_meta_v1"
        private const val REMINDERS = "flutter.echo_reminders_v1"
    }
}
