package com.chandangs.echo

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.text.BreakIterator
import java.util.Calendar

/**
 * Who's waiting on a reply, as the widgets see it. The app publishes the real
 * list (WaitingStore) to `widget_waiting_v1` whenever it runs. In between,
 * the notification listener feeds [observe], which applies the same rules
 * (WaitingIntent) so a message that arrives while the app is closed still
 * shows up, and a reply sent from the chat app still clears the face. Nothing
 * here leaves the phone.
 */
object WaitingWidgetData {
    private const val TAG = "EchoWaitingWidget"
    private const val SNAPSHOT_KEY = "flutter.widget_waiting_v1"

    // Kept apart from Flutter's file: the snapshot belongs to Dart, this to the listener.
    private const val OVERLAY_PREFS = "echo_widget_waiting"
    private const val KEY_ITEMS = "items"
    private const val KEY_REPLIED = "replied"

    private const val DEFAULT_RETENTION_DAYS = 7L
    private const val MAX_OVERLAY = 40

    /** Group replies: how long after the owner spoke a message still reads as an answer. */
    private const val REPLY_WINDOW_MS = 30 * 60_000L

    private val tints = intArrayOf(
        0xFF7C6BB0.toInt(), 0xFF3E8E7E.toInt(), 0xFFC2703D.toInt(), 0xFF4F7CB4.toInt(),
        0xFFB0527A.toInt(), 0xFF5E8F4E.toInt(), 0xFF6B6F7A.toInt(), 0xFF9A7B3E.toInt(),
        0xFFA8604F.toInt(),
    )

    data class Person(
        val name: String,
        val sender: String,
        val source: String,
        val thread: String?,
        val since: Long,
    )

    /** [known] is false until the app has published a list at least once. */
    data class Waiting(val people: List<Person>, val known: Boolean)

    /** The same name always lands on the same tint as PersonAvatar. */
    fun tintFor(name: String): Int {
        var hash = 0x811C9DC5L
        for (unit in name.trim().lowercase()) {
            hash = ((hash xor unit.code.toLong()) * 0x01000193L) and 0xFFFFFFFFL
        }
        return tints[(hash % tints.size).toInt()]
    }

    /** The first letter or digit, whatever the script; an emoji stays an emoji. */
    fun initial(name: String): String {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return "?"
        val it = BreakIterator.getCharacterInstance()
        it.setText(trimmed)
        var start = it.first()
        var end = it.next()
        while (end != BreakIterator.DONE) {
            val cluster = trimmed.substring(start, end)
            if (cluster.any { c -> c.isLetterOrDigit() }) return cluster.uppercase()
            start = end
            end = it.next()
        }
        return trimmed.substring(0, trimmed.offsetByCodePoints(0, 1))
    }

    /** First name, or the app when there's no sender at all. */
    fun shortName(person: Person): String =
        person.name.trim().split(Regex("\\s+")).firstOrNull()?.takeIf { it.isNotEmpty() } ?: person.source

    private fun midnight(ts: Long): Long = Calendar.getInstance().apply {
        timeInMillis = ts
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }.timeInMillis

    /** Whole calendar days since [ts]: 0 today, 1 yesterday. */
    fun daysSince(ts: Long, now: Long): Int =
        Math.round((midnight(now) - midnight(ts)) / 86_400_000.0).toInt().coerceAtLeast(0)

    /** 0 fresh, 1 since yesterday, 2 two days or more. */
    fun ageBand(since: Long, now: Long): Int = daysSince(since, now).coerceAtMost(2)

    /** How full the ring is: a third in an hour, nearly all of it in two days (WaitingStore). */
    fun ageProgress(since: Long, now: Long): Float {
        val hours = ((now - since).coerceAtLeast(0L)) / 3_600_000f
        if (hours <= 0f) return 0.06f
        return (0.3f * Math.pow(hours.toDouble(), 0.29).toFloat()).coerceIn(0.06f, 1f)
    }

    /** "40m", "5h", "2d". */
    fun shortSince(since: Long, now: Long): String {
        val minutes = ((now - since).coerceAtLeast(0L)) / 60_000
        return when {
            minutes < 1 -> "now"
            minutes < 60 -> "${minutes}m"
            minutes < 24 * 60 -> "${minutes / 60}h"
            else -> "${minutes / (24 * 60)}d"
        }
    }

    fun oldestDays(waiting: Waiting, now: Long): Int =
        waiting.people.minOfOrNull { it.since }?.let { daysSince(it, now) } ?: 0

    @Synchronized
    fun load(context: Context, now: Long = System.currentTimeMillis()): Waiting {
        val prefs = WidgetData.prefs(context)
        val raw = prefs.getString(SNAPSHOT_KEY, null)
        val (publishedAt, snapshot) = parseSnapshot(raw)
        val overlay = context.getSharedPreferences(OVERLAY_PREFS, Context.MODE_PRIVATE)
        val added = readOverlayItems(overlay.getString(KEY_ITEMS, null))
        val replied = readReplied(overlay.getString(KEY_REPLIED, null))

        val maxAgeMs = retentionDays(prefs) * 86_400_000L
        val people = LinkedHashMap<String, Person>()
        fun add(p: Person) {
            if (now - p.since > maxAgeMs) return
            val answeredAt = p.thread?.let { replied[it] }
            if (answeredAt != null && answeredAt >= p.since) return
            val id = identity(p)
            val existing = people[id]
            people[id] = if (existing == null || p.since < existing.since) p else existing
        }
        snapshot.forEach { add(it) }
        // Whatever the app has already seen is in the snapshot.
        added.filter { it.since > publishedAt }.forEach { add(it) }
        val sorted = people.values.sortedBy { it.since }
        return Waiting(sorted, known = raw != null || added.isNotEmpty())
    }

    /** The user's retention setting: a face can't outlive the message behind it. */
    private fun retentionDays(prefs: android.content.SharedPreferences): Long {
        val days = WidgetData.readLongOrInt(prefs, "flutter.retention_days")
        return if (days > 0) days else DEFAULT_RETENTION_DAYS
    }

    private fun identity(p: Person): String =
        p.thread?.takeIf { it.isNotEmpty() } ?: "${p.source.lowercase()}:${p.sender.trim().lowercase()}"

    private fun parseSnapshot(raw: String?): Pair<Long, List<Person>> {
        if (raw == null) return 0L to emptyList()
        return try {
            val json = JSONObject(raw)
            json.optLong("at", 0L) to parsePeople(json.optJSONArray("items"))
        } catch (e: Exception) {
            Log.e(TAG, "Unreadable waiting list", e)
            0L to emptyList()
        }
    }

    private fun parsePeople(array: JSONArray?): List<Person> {
        if (array == null) return emptyList()
        return (0 until array.length()).mapNotNull { i ->
            val o = array.optJSONObject(i) ?: return@mapNotNull null
            val sender = o.optString("sender")
            val source = o.optString("source")
            val since = o.optLong("since", 0L)
            if (since <= 0L) return@mapNotNull null
            Person(
                name = o.optString("name").ifBlank { sender.ifBlank { source } },
                sender = sender,
                source = source,
                thread = o.optString("thread").takeIf { it.isNotEmpty() },
                since = since,
            )
        }
    }

    private fun readOverlayItems(raw: String?): List<Person> =
        if (raw == null) emptyList() else try {
            parsePeople(JSONArray(raw))
        } catch (e: Exception) {
            emptyList()
        }

    private fun readReplied(raw: String?): Map<String, Long> {
        if (raw == null) return emptyMap()
        return try {
            val json = JSONObject(raw)
            json.keys().asSequence().associateWith { json.getLong(it) }
        } catch (e: Exception) {
            emptyMap()
        }
    }

    /**
     * Takes one captured message off the listener. Quiet unless it changes
     * who's on the widget, so a busy group doesn't redraw the home screen on
     * every line.
     */
    @Synchronized
    fun observe(context: Context, message: JSONObject) {
        if (message.has("kind") || !message.has("isGroup")) return
        val thread = message.optString("thread")
        if (thread.isEmpty()) return
        val isGroup = message.optBoolean("isGroup", false)
        val ts = message.optLong("timestamp", System.currentTimeMillis())
        val prefs = context.getSharedPreferences(OVERLAY_PREFS, Context.MODE_PRIVATE)
        val replied = JSONObject(readReplied(prefs.getString(KEY_REPLIED, null)))
        val before = signature(load(context))

        if (message.optBoolean("fromMe", false)) {
            replied.put(thread, ts)
            val items = readOverlayItems(prefs.getString(KEY_ITEMS, null)).filterNot { it.thread == thread }
            prefs.edit().putString(KEY_REPLIED, trimReplied(replied).toString())
                .putString(KEY_ITEMS, toJson(items).toString()).apply()
        } else {
            val text = message.optString("content")
            val addressed = when {
                !isGroup -> "direct"
                mentionsOwner(context, text, message.optString("selfName")) -> "mentioned"
                ts - replied.optLong(thread, 0L) in 0..REPLY_WINDOW_MS -> "reply"
                else -> "group"
            }
            if (addressed == "group") return
            // Unclear ones stay on until the app's model has looked at them,
            // same as the list in the app.
            if (!WaitingIntent.classify(text, isGroup, addressed).needsReply) return
            val sender = message.optString("sender").ifBlank { message.optString("threadTitle") }
            if (sender.isBlank()) return
            val person = Person(
                name = sender,
                sender = sender,
                source = message.optString("source"),
                thread = thread,
                since = ts,
            )
            val items = readOverlayItems(prefs.getString(KEY_ITEMS, null)).toMutableList()
            val existing = items.indexOfFirst { it.thread == thread }
            if (existing >= 0) {
                if (ts < items[existing].since) items[existing] = person
            } else {
                items.add(person)
            }
            prefs.edit().putString(KEY_ITEMS, toJson(items.takeLast(MAX_OVERLAY)).toString()).apply()
        }

        if (signature(load(context)) != before) WidgetData.refreshAll(context)
    }

    private fun signature(w: Waiting): String =
        w.people.joinToString("|") { "${identity(it)}@${it.since}" }

    /** "@Chandan" or "chandan," but not "Chandana"; names under 3 letters are ignored. */
    private fun mentionsOwner(context: Context, text: String, selfName: String): Boolean {
        val user = WidgetData.prefs(context).getString("flutter.user_name", null).orEmpty().trim()
        val names = listOf(user, user.split(Regex("\\s+")).firstOrNull().orEmpty(), selfName.trim())
        return names.filter { it.length >= 3 }.any { name ->
            Regex("(?<![\\p{L}\\p{N}])@?" + Regex.escape(name) + "(?![\\p{L}\\p{N}])", RegexOption.IGNORE_CASE)
                .containsMatchIn(text)
        }
    }

    private fun trimReplied(replied: JSONObject): JSONObject {
        if (replied.length() <= 60) return replied
        val keep = replied.keys().asSequence().toList()
            .sortedByDescending { replied.optLong(it, 0L) }.take(40)
        return JSONObject(keep.associateWith { replied.optLong(it, 0L) })
    }

    private fun toJson(items: List<Person>): JSONArray = JSONArray().apply {
        items.forEach {
            put(JSONObject().apply {
                put("name", it.name)
                put("sender", it.sender)
                put("source", it.source)
                put("thread", it.thread ?: "")
                put("since", it.since)
            })
        }
    }
}
