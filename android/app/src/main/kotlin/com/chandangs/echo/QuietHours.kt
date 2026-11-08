package com.chandangs.echo

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Resources
import android.graphics.drawable.Icon
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import java.util.TimeZone

/**
 * When quiet hours run, worked out from the owner's settings (Dart's
 * QuietConfig; the same rules and test vectors live in quiet_settings.dart).
 */
object QuietSchedule {
    data class Config(
        val enabled: Boolean,
        val startMin: Int,
        val endMin: Int,
        /** Days a window may start on, 1 = Monday … 7 = Sunday. */
        val days: Set<Int>,
        val people: Boolean,
        val calendar: Boolean,
        val deliveries: Boolean,
        /** Lowercased names that always get through. */
        val through: Set<String>,
        /** Lowercased names that mean the owner. */
        val names: Set<String>,
    )

    data class Window(val start: Long, val end: Long)

    /** The window [now] falls in: today's, or yesterday's if it ran past midnight. */
    fun activeWindow(c: Config, now: Long, zone: TimeZone = TimeZone.getDefault()): Window? {
        if (!c.enabled || c.startMin == c.endMin) return null
        for (daysBack in 0..1) {
            val day = Calendar.getInstance(zone).apply {
                timeInMillis = now
                add(Calendar.DAY_OF_MONTH, -daysBack)
            }
            if (isoDay(day) !in c.days) continue
            val start = at(day, c.startMin, 0)
            val end = at(day, c.endMin, if (c.endMin > c.startMin) 0 else 1)
            if (now in start until end) return Window(start, end)
        }
        return null
    }

    private fun isoDay(c: Calendar): Int = ((c.get(Calendar.DAY_OF_WEEK) + 5) % 7) + 1

    private fun at(day: Calendar, minutes: Int, addDays: Int): Long =
        (day.clone() as Calendar).apply {
            add(Calendar.DAY_OF_MONTH, addDays)
            set(Calendar.HOUR_OF_DAY, minutes / 60)
            set(Calendar.MINUTE, minutes % 60)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
}

/**
 * Quiet hours: notifications that aren't for the owner are snoozed until the
 * window ends and come back from Android unchanged, with their own actions.
 *
 * The rule throughout is that nothing can be lost. Only a notification Echo
 * has just captured is ever held, so History always has a copy; the hold is
 * Android's own timer, so Echo dying changes nothing; and if a snooze doesn't
 * take, the notification simply stays in the shade.
 *
 * Runs in the listener and in [QuietHoursReceiver], on the main thread, with
 * its state in its own prefs so a restart mid-window picks up where it was.
 */
object QuietHours {
    const val DIGEST_ID = 774_100
    const val ACTION_CLOSE = "com.chandangs.echo.QUIET_CLOSE"
    const val ACTION_CLEAR = "com.chandangs.echo.QUIET_CLEAR"

    private const val TAG = "EchoQuiet"
    private const val CONFIG_KEY = "flutter.quiet_config_v1"
    private const val USER_NAME_KEY = "flutter.user_name"
    private const val TURNS_KEY = "flutter.echo_my_turns_v1"
    private const val STATE_KEY = "state_v1"
    private const val CHANNEL = "echo_quiet_digest"
    private const val METHOD_CHANNEL = "project_echo/quiet"

    private const val DAY_MS = 24 * 60 * 60 * 1000L

    /** A snooze ending this close to the window's end counts as ended. */
    private const val GRACE_MS = 5_000L

    /** Back within this long of holding it: the phone didn't really hold it. */
    private const val INSTANT_RETURN_MS = 30_000L

    /** How long a snooze gets to show up before it's checked. */
    private const val VERIFY_MS = 4_000L

    /** Snoozes in a row that may fail before Echo stops trying this window. */
    private const val MAX_FAILURES = 3

    /** Android refuses more snoozed notifications than this. */
    private const val MAX_KEYS = 480

    private const val ALARM_WINDOW_MS = 10 * 60 * 1000L
    private const val REPLY_WINDOW_MS = 30 * 60 * 1000L

    enum class Kind {
        /** Goes through as usual. */
        PASS,

        /** Captured, then snoozed until [Verdict.until]. */
        HOLD,

        /** Back from a hold, exactly as it was: already captured. */
        RETURNED,

        /** Back from a hold, updated while it was held. */
        RETURNED_CHANGED,
    }

    data class Verdict(val kind: Kind, val until: Long = 0L) {
        /** Whether what's captured from it counts as held. */
        val held: Boolean get() = kind != Kind.PASS
    }

    /** What the listener read from a notification, for deciding about it. */
    data class Facts(
        val sender: String,
        val text: String,
        val isChat: Boolean,
        val isGroup: Boolean,
        val thread: String?,
        val selfName: String?,
        /** False for a chat notification with nothing new in it. */
        val fresh: Boolean = true,
        /** Messages this notification brings. */
        val count: Int = 1,
    )

    private val handler by lazy { Handler(Looper.getMainLooper()) }

    // ── The decision ──────────────────────────────────────────────────────

    /** Decides what happens to the just-posted [sbn]. */
    @Synchronized
    fun judge(service: NotificationListenerService, sbn: StatusBarNotification, facts: Facts): Verdict {
        val context = service.applicationContext
        if (sbn.packageName == context.packageName) return Verdict(Kind.PASS)
        val now = System.currentTimeMillis()
        val state = state(context)
        val held = state.heldMap().optJSONObject(sbn.key)
        if (held != null) {
            state.heldMap().remove(sbn.key)
            val until = held.optLong("until")
            val released = held.optBoolean("releasing") || now >= until - GRACE_MS
            when {
                released -> {
                    save(context)
                    closeIfDue(context, now)
                    val same = held.optString("hash") == hash(facts)
                    return Verdict(if (same) Kind.RETURNED else Kind.RETURNED_CHANGED)
                }
                now - held.optLong("at") < INSTANT_RETURN_MS -> {
                    Log.w(TAG, "Android gave a notification straight back")
                    noteFailure(state, held)
                    save(context)
                    tellNotHeld(service, sbn.key, now)
                    return Verdict(Kind.PASS)
                }
                // The app took it back and has posted it anew: judged afresh.
                else -> save(context)
            }
        }
        closeIfDue(context, now)
        if (!facts.fresh) return Verdict(Kind.PASS)
        val config = config(context) ?: return Verdict(Kind.PASS)
        val window = QuietSchedule.activeWindow(config, now) ?: return Verdict(Kind.PASS)
        if (state.optBoolean("blocked")) return Verdict(Kind.PASS)
        if (state.heldMap().length() >= MAX_KEYS) return Verdict(Kind.PASS)
        if (getsThrough(service, sbn, facts, config, now)) {
            noteThrough(context, facts, config, window, now)
            return Verdict(Kind.PASS)
        }
        return Verdict(Kind.HOLD, window.end)
    }

    private fun getsThrough(
        service: NotificationListenerService,
        sbn: StatusBarNotification,
        facts: Facts,
        config: QuietSchedule.Config,
        now: Long,
    ): Boolean {
        val n = sbn.notification ?: return true
        if (ringsThrough(sbn, n)) return true
        if (isCodeOrHidden(facts.text)) return true
        if (facts.sender.trim().lowercase() in config.through) return true
        if (facts.isChat && facts.thread != null && config.people) {
            if (!facts.isGroup) return true
            if (mentionsOwner(service, facts, config)) return true
            if (spokeRecently(service, facts.thread, now)) return true
        }
        if (config.calendar && isCalendar(sbn, n)) return true
        if (config.deliveries && isDelivery(sbn.packageName, facts.text)) return true
        return false
    }

    /** Calls, alarms and anything else Android runs live: never touched. */
    private fun ringsThrough(sbn: StatusBarNotification, n: Notification): Boolean {
        if (n.category in LIVE_CATEGORIES) return true
        if (n.fullScreenIntent != null) return true
        val live = Notification.FLAG_INSISTENT or Notification.FLAG_FOREGROUND_SERVICE or
            Notification.FLAG_NO_CLEAR or Notification.FLAG_ONGOING_EVENT
        if (n.flags and live != 0) return true
        if (n.extras?.containsKey(Notification.EXTRA_MEDIA_SESSION) == true) return true
        val pkg = sbn.packageName
        return LIVE_PACKAGES.any { pkg.contains(it) }
    }

    /**
     * A one-time code, or text Android has hidden from Echo. It can't be told
     * what a hidden notification says, so every one of those goes through.
     */
    private fun isCodeOrHidden(text: String): Boolean {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return true
        if (trimmed == redactedText) return true
        if (trimmed.contains("sensitive notification content", ignoreCase = true)) return true
        return CODE_WORDS.containsMatchIn(trimmed) && CODE_DIGITS.containsMatchIn(trimmed)
    }

    /** What Android 15 and later replace a code notification's text with. */
    private val redactedText: String? by lazy {
        try {
            val res = Resources.getSystem()
            val id = res.getIdentifier("redacted_notification_message", "string", "android")
            if (id == 0) null else res.getString(id).trim()
        } catch (e: Exception) {
            null
        }
    }

    private fun isCalendar(sbn: StatusBarNotification, n: Notification): Boolean =
        n.category == Notification.CATEGORY_EVENT ||
            n.category == Notification.CATEGORY_REMINDER ||
            sbn.packageName.contains("calendar", ignoreCase = true)

    private fun isDelivery(pkg: String, text: String): Boolean =
        DELIVERY_PACKAGES.any { pkg.contains(it, ignoreCase = true) } || DELIVERY_WORDS.containsMatchIn(text)

    private fun mentionsOwner(context: Context, facts: Facts, config: QuietSchedule.Config): Boolean {
        val names = HashSet(config.names)
        facts.selfName?.let { names.add(it.lowercase()) }
        prefs(context).getString(USER_NAME_KEY, null)?.trim()?.lowercase()?.let {
            names.add(it)
            names.add(it.split(Regex("\\s+")).first())
        }
        return names.filter { it.length >= 3 && it !in GENERIC_NAMES }.any { name ->
            Regex(
                "(?<![\\p{L}\\p{N}])@?${Regex.escape(name)}(?![\\p{L}\\p{N}])",
                RegexOption.IGNORE_CASE,
            ).containsMatchIn(facts.text)
        }
    }

    private var cachedTurnsRaw: String? = null
    private var cachedTurns = JSONObject()

    /** Whether the owner wrote in [thread] in the last half hour. */
    private fun spokeRecently(context: Context, thread: String, now: Long): Boolean {
        val raw = prefs(context).getString(TURNS_KEY, null) ?: return false
        if (raw != cachedTurnsRaw) {
            cachedTurnsRaw = raw
            cachedTurns = try {
                JSONObject(raw)
            } catch (e: Exception) {
                JSONObject()
            }
        }
        val turns = cachedTurns.optJSONArray(thread) ?: return false
        if (turns.length() == 0) return false
        val last = turns.optJSONObject(turns.length() - 1)?.optLong("t") ?: return false
        return now - last in 0..REPLY_WINDOW_MS
    }

    // ── Holding ───────────────────────────────────────────────────────────

    /** Snoozes [sbn] until [until]. If that can't happen it stays in the shade. */
    @Synchronized
    fun hold(service: NotificationListenerService, sbn: StatusBarNotification, facts: Facts, until: Long) {
        val context = service.applicationContext
        val now = System.currentTimeMillis()
        val config = config(context) ?: return
        val window = QuietSchedule.activeWindow(config, now) ?: return
        val entry = JSONObject()
            .put("at", now)
            .put("until", until)
            .put("hash", hash(facts))
            .put("count", facts.count)
            .put("kind", digestKind(sbn.packageName, facts))
        try {
            state(context).heldMap().put(sbn.key, entry)
            count(context, sbn.key, window, entry, now)
            save(context)
            service.snoozeNotification(sbn.key, (until - now).coerceIn(1_000L, DAY_MS))
        } catch (e: Exception) {
            Log.w(TAG, "Couldn't hold a notification: ${e.message}")
            val state = state(context)
            state.heldMap().remove(sbn.key)
            noteFailure(state, entry)
            save(context)
            tellNotHeld(service, sbn.key, now)
            return
        }
        scheduleClose(context, until)
        handler.postDelayed({ verify(service, sbn.key) }, VERIFY_MS)
    }

    /** Whether a snooze actually took: is the notification still showing? */
    @Synchronized
    private fun verify(service: NotificationListenerService, key: String) {
        val context = service.applicationContext
        val state = state(context)
        val entry = state.heldMap().optJSONObject(key) ?: return
        if (entry.optBoolean("confirmed")) return
        val showing = try {
            service.getActiveNotifications(arrayOf(key)).orEmpty().isNotEmpty()
        } catch (e: Exception) {
            return
        }
        if (!showing) return
        Log.w(TAG, "A snooze didn't take on this phone")
        state.heldMap().remove(key)
        noteFailure(state, entry)
        save(context)
        tellNotHeld(service, key, System.currentTimeMillis())
    }

    /** A removal Echo's snooze caused is the confirmation that it worked. */
    @Synchronized
    fun onRemoved(context: Context, key: String, reason: Int) {
        if (reason != NotificationListenerService.REASON_SNOOZED) return
        val state = state(context)
        val entry = state.heldMap().optJSONObject(key) ?: return
        entry.put("confirmed", true)
        state.put("failures", 0)
        save(context)
    }

    /** Takes back the "held" mark on a notification that wasn't held after all. */
    private fun tellNotHeld(service: NotificationListenerService, key: String, now: Long) {
        (service as? EchoNotificationListenerService)?.emit(
            JSONObject()
                .put("kind", "removal")
                .put("noticeKey", key)
                .put("how", "notHeld")
                .put("timestamp", now),
        )
    }

    private fun noteFailure(state: JSONObject, entry: JSONObject) {
        val session = state.optJSONObject("session")
        if (session != null) uncount(session, entry)
        val failures = state.optInt("failures") + 1
        state.put("failures", failures)
        if (failures >= MAX_FAILURES) state.put("blocked", true)
    }

    // ── The session: what one window has held so far ──────────────────────

    private fun openSession(context: Context, window: QuietSchedule.Window, now: Long): JSONObject {
        val state = state(context)
        state.optJSONObject("session")?.let { return it }
        val session = JSONObject()
            .put("since", now)
            .put("start", window.start)
            .put("end", window.end)
            .put("count", 0)
            .put("groups", 0)
            .put("deliveries", 0)
            .put("other", 0)
            .put("through", JSONArray())
            .put("keys", JSONArray())
            .put("boot", bootCount(context))
        state.put("session", session)
        return session
    }

    private fun count(context: Context, key: String, window: QuietSchedule.Window, entry: JSONObject, now: Long) {
        val session = openSession(context, window, now)
        val n = entry.optInt("count", 1)
        session.put("count", session.optInt("count") + n)
        val kind = entry.optString("kind", "other")
        session.put(kind, session.optInt(kind) + n)
        session.optJSONArray("keys")?.let { if (it.length() < MAX_KEYS) it.put(key) }
    }

    private fun uncount(session: JSONObject, entry: JSONObject) {
        val n = entry.optInt("count", 1)
        session.put("count", (session.optInt("count") - n).coerceAtLeast(0))
        val kind = entry.optString("kind", "other")
        session.put(kind, (session.optInt(kind) - n).coerceAtLeast(0))
    }

    private fun digestKind(pkg: String, facts: Facts): String = when {
        facts.isChat && facts.isGroup -> "groups"
        isDelivery(pkg, facts.text) -> "deliveries"
        else -> "other"
    }

    private fun noteThrough(
        context: Context,
        facts: Facts,
        config: QuietSchedule.Config,
        window: QuietSchedule.Window,
        now: Long,
    ) {
        if (!facts.isChat || facts.sender.isBlank()) return
        val session = openSession(context, window, now)
        val through = session.optJSONArray("through") ?: JSONArray().also { session.put("through", it) }
        val name = facts.sender.trim()
        if ((0 until through.length()).any { through.optString(it) == name }) return
        if (through.length() < 8) {
            through.put(name)
            save(context)
        }
    }

    /** Sends the digest and ends the session once its window is over. */
    private fun closeIfDue(context: Context, now: Long) {
        val session = state(context).optJSONObject("session") ?: return
        if (now >= session.optLong("end")) close(context, now)
    }

    private fun close(context: Context, now: Long) {
        val state = state(context)
        val session = state.optJSONObject("session") ?: return
        state.remove("session")
        state.put("failures", 0)
        state.put("blocked", false)
        // Anything long past its time isn't coming back: drop the note of it.
        val held = state.heldMap()
        for (key in held.keys().asSequence().toList()) {
            if (now - (held.optJSONObject(key)?.optLong("until") ?: 0L) > DAY_MS) held.remove(key)
        }
        session.put("closedAt", now)
        if (session.optInt("count") > 0) {
            state.put("lastDigest", session)
            save(context)
            postDigest(context, session)
        } else {
            save(context)
        }
        cancelClose(context)
    }

    private fun postDigest(context: Context, session: JSONObject) {
        val count = session.optInt("count")
        val parts = listOfNotNull(
            session.optInt("groups").takeIf { it > 0 }?.let { "$it group ${if (it == 1) "message" else "messages"}" },
            session.optInt("deliveries").takeIf { it > 0 }?.let { "$it ${if (it == 1) "delivery" else "deliveries"}" },
            session.optInt("other").takeIf { it > 0 }?.let { "$it ${if (it == 1) "update" else "updates"}" },
        )
        val lead = if (session.optBoolean("restarted")) {
            "Your phone restarted while these were held, so read them here."
        } else {
            "Nothing else needs you."
        }
        val body = "$lead ${parts.joinToString(", ")}."
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL, "Quiet hours", NotificationManager.IMPORTANCE_LOW)
                .apply { description = "One note when quiet hours end" },
        )
        val open = PendingIntent.getActivity(
            context,
            DIGEST_ID,
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                .putExtra(WidgetData.EXTRA_ROUTE, "/digest"),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val clear = PendingIntent.getBroadcast(
            context,
            DIGEST_ID,
            Intent(context, QuietHoursReceiver::class.java).setAction(ACTION_CLEAR),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val icon = Icon.createWithResource(context, R.drawable.ic_notification)
        manager.notify(
            DIGEST_ID,
            Notification.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle("While you were quiet: $count ${if (count == 1) "notification" else "notifications"}")
                .setContentText(body)
                .setStyle(Notification.BigTextStyle().bigText(body))
                .setAutoCancel(true)
                .setContentIntent(open)
                .addAction(Notification.Action.Builder(icon, "Show all", open).build())
                .addAction(Notification.Action.Builder(icon, "Clear", clear).build())
                .build(),
        )
    }

    // ── Things that change the plan ───────────────────────────────────────

    /** The listener is back: catch up on anything that happened without it. */
    @Synchronized
    fun onListenerConnected(service: NotificationListenerService) {
        val context = service.applicationContext
        val now = System.currentTimeMillis()
        val session = state(context).optJSONObject("session")
        if (session != null && session.optInt("boot", -1) != bootCount(context)) markRestarted(context)
        closeIfDue(context, now)
        state(context).optJSONObject("session")?.let { scheduleClose(context, it.optLong("end")) }
    }

    /** Asks Android to bring the listener back while quiet hours are running. */
    fun onListenerDisconnected(service: NotificationListenerService) {
        val context = service.applicationContext
        val config = config(context) ?: return
        if (QuietSchedule.activeWindow(config, System.currentTimeMillis()) == null) return
        try {
            NotificationListenerService.requestRebind(
                ComponentName(context, EchoNotificationListenerService::class.java),
            )
        } catch (e: Exception) {
            Log.w(TAG, "Couldn't ask for the listener back: ${e.message}")
        }
    }

    /** A restart clears Android's snoozes and every alarm. */
    @Synchronized
    fun onBoot(context: Context) {
        markRestarted(context)
        val now = System.currentTimeMillis()
        closeIfDue(context, now)
        state(context).optJSONObject("session")?.let { scheduleClose(context, it.optLong("end")) }
    }

    private fun markRestarted(context: Context) {
        val state = state(context)
        val held = state.heldMap()
        val session = state.optJSONObject("session")
        if (session != null && held.length() > 0) session.put("restarted", true)
        session?.put("boot", bootCount(context))
        state.put("held", JSONObject())
        save(context)
    }

    /** An app update clears alarms, but Android's snoozes carry on. */
    @Synchronized
    fun onUpdated(context: Context) {
        closeIfDue(context, System.currentTimeMillis())
        state(context).optJSONObject("session")?.let { scheduleClose(context, it.optLong("end")) }
    }

    /** The end-of-window alarm. */
    @Synchronized
    fun onAlarm(context: Context) {
        val now = System.currentTimeMillis()
        closeIfDue(context, now)
        // Fired early (the clock moved): come back at the real end.
        state(context).optJSONObject("session")?.let { scheduleClose(context, it.optLong("end")) }
    }

    /**
     * The settings or the clock changed: what's held follows the window as
     * it now stands. Android may refuse to shorten a snooze; those come back
     * at their original time instead.
     */
    @Synchronized
    fun reconcile(context: Context) {
        val state = state(context)
        val session = state.optJSONObject("session") ?: return
        val now = System.currentTimeMillis()
        val window = config(context)?.let { QuietSchedule.activeWindow(it, now) }
        if (window == null) {
            release(context, now)
            close(context, now)
            return
        }
        if (window.end == session.optLong("end")) return
        session.put("end", window.end)
        val service = EchoNotificationListenerService.instance
        val held = state.heldMap()
        for (key in held.keys().asSequence().toList()) {
            held.optJSONObject(key)?.put("until", window.end)
            try {
                service?.snoozeNotification(key, (window.end - now).coerceIn(1_000L, DAY_MS))
            } catch (e: Exception) {
                Log.w(TAG, "Couldn't move a hold: ${e.message}")
            }
        }
        save(context)
        scheduleClose(context, window.end)
    }

    /** Hands everything held back now. Returns how many were asked for, or -1 without the listener. */
    @Synchronized
    fun deliverNow(context: Context): Int {
        if (EchoNotificationListenerService.instance == null) return -1
        val now = System.currentTimeMillis()
        val asked = release(context, now)
        close(context, now)
        return asked
    }

    /** Re-snoozes everything held for a moment, which ends the hold sooner. */
    private fun release(context: Context, now: Long): Int {
        val service = EchoNotificationListenerService.instance ?: return 0
        val state = state(context)
        val held = state.heldMap()
        var asked = 0
        for (key in held.keys().asSequence().toList()) {
            val entry = held.optJSONObject(key) ?: continue
            if (now >= entry.optLong("until")) continue
            try {
                service.snoozeNotification(key, 1_000L)
                entry.put("releasing", true)
                asked++
            } catch (e: Exception) {
                Log.w(TAG, "Couldn't release a hold: ${e.message}")
            }
        }
        save(context)
        return asked
    }

    /** Clears the digest, and what came back with it, from the shade. */
    @Synchronized
    fun clearDigest(context: Context) {
        context.getSystemService(NotificationManager::class.java).cancel(DIGEST_ID)
        val keys = state(context).optJSONObject("lastDigest")?.optJSONArray("keys") ?: return
        val service = EchoNotificationListenerService.instance ?: return
        try {
            service.cancelNotifications(Array(keys.length()) { keys.getString(it) })
        } catch (e: Exception) {
            Log.w(TAG, "Couldn't clear the shade: ${e.message}")
        }
    }

    // ── Dart ──────────────────────────────────────────────────────────────

    fun attachChannel(messenger: BinaryMessenger, context: Context) {
        val app = context.applicationContext
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(status(app))
                "sync" -> {
                    reconcile(app)
                    result.success(status(app))
                }
                "deliverNow" -> result.success(deliverNow(app))
                "clearDigest" -> {
                    clearDigest(app)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    @Synchronized
    private fun status(context: Context): String {
        val state = state(context)
        return JSONObject()
            .put("session", state.optJSONObject("session") ?: JSONObject.NULL)
            .put("lastDigest", state.optJSONObject("lastDigest") ?: JSONObject.NULL)
            .put("blocked", state.optBoolean("blocked"))
            .put("listening", EchoNotificationListenerService.instance != null)
            .toString()
    }

    // ── Alarm and storage ─────────────────────────────────────────────────

    private fun closeAlarm(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context,
        DIGEST_ID + 1,
        Intent(context, QuietHoursReceiver::class.java).setAction(ACTION_CLOSE),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    /**
     * A backstop for the digest; normally the first notification returning
     * sends it. Windowed like reminders, needing no exact-alarm permission.
     */
    private fun scheduleClose(context: Context, at: Long) {
        context.getSystemService(AlarmManager::class.java)
            .setWindow(AlarmManager.RTC_WAKEUP, at + GRACE_MS, ALARM_WINDOW_MS, closeAlarm(context))
    }

    private fun cancelClose(context: Context) {
        context.getSystemService(AlarmManager::class.java).cancel(closeAlarm(context))
    }

    private fun bootCount(context: Context): Int = try {
        Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT, 0)
    } catch (e: Exception) {
        0
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    private var cached: JSONObject? = null

    private fun state(context: Context): JSONObject {
        cached?.let { return it }
        val raw = context.getSharedPreferences("echo_quiet", Context.MODE_PRIVATE).getString(STATE_KEY, null)
        val loaded = try {
            JSONObject(raw ?: "{}")
        } catch (e: Exception) {
            JSONObject()
        }
        if (!loaded.has("held")) loaded.put("held", JSONObject())
        cached = loaded
        return loaded
    }

    private fun JSONObject.heldMap(): JSONObject = getJSONObject("held")

    private fun save(context: Context) {
        context.getSharedPreferences("echo_quiet", Context.MODE_PRIVATE).edit()
            .putString(STATE_KEY, state(context).toString())
            .apply()
    }

    private fun hash(facts: Facts): String = ConversationReader.shortHash("${facts.sender}\n${facts.text}")

    /** The owner's settings, or null when quiet hours are off or unreadable. */
    private fun config(context: Context): QuietSchedule.Config? {
        val raw = prefs(context).getString(CONFIG_KEY, null) ?: return null
        return try {
            val j = JSONObject(raw)
            if (!j.optBoolean("enabled")) return null
            QuietSchedule.Config(
                enabled = true,
                startMin = j.getInt("startMin"),
                endMin = j.getInt("endMin"),
                days = j.getJSONArray("days").let { a -> (0 until a.length()).map { a.getInt(it) }.toSet() },
                people = j.optBoolean("people", true),
                calendar = j.optBoolean("calendar", true),
                deliveries = j.optBoolean("deliveries", false),
                through = j.optJSONArray("through").lowercased(),
                names = j.optJSONArray("names").lowercased(),
            )
        } catch (e: Exception) {
            Log.w(TAG, "Unreadable quiet hours settings: ${e.message}")
            null
        }
    }

    private fun JSONArray?.lowercased(): Set<String> {
        if (this == null) return emptySet()
        return (0 until length()).map { getString(it).trim().lowercase() }.toSet()
    }

    private val GENERIC_NAMES = setOf("you", "me", "myself")

    private val LIVE_CATEGORIES = setOf(
        "call", "missed_call", "alarm", "navigation", "service", "sys", "transport",
        "progress", "err", "status", "stopwatch", "location_sharing", "workout",
    )

    private val LIVE_PACKAGES = listOf("deskclock", "dialer", "telecom", "incallui", "com.android.phone", "alarmclock")

    private val CODE_WORDS = Regex(
        """\b(otp|one[- ]?time|verification|verify|passcode|security code|login code|auth(entication)? code|2fa|pin|code)\b|ओटीपी|सत्यापन""",
        RegexOption.IGNORE_CASE,
    )
    private val CODE_DIGITS = Regex("""(?<!\d)(\d{4,8}|\d{3}[ -]\d{3})(?!\d)""")

    private val DELIVERY_PACKAGES = listOf(
        "swiggy", "zomato", "blinkit", "grofers", "zepto", "bigbasket", "dunzo",
        "amazon", "flipkart", "delhivery", "bluedart", "dtdc", "ekart", "myntra",
    )
    private val DELIVERY_WORDS = Regex(
        """out for delivery|been delivered|was delivered|has shipped|been shipped|dispatched|order (is )?(picked|confirmed|arriving|on the way)""",
        RegexOption.IGNORE_CASE,
    )
}

/**
 * Keeps quiet hours right through what clears alarms or moves the clock, and
 * takes the end-of-window alarm and the digest's Clear button.
 */
class QuietHoursReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED -> QuietHours.onBoot(context)
            Intent.ACTION_MY_PACKAGE_REPLACED -> QuietHours.onUpdated(context)
            Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_TIME_CHANGED -> QuietHours.reconcile(context)
            QuietHours.ACTION_CLOSE -> QuietHours.onAlarm(context)
            QuietHours.ACTION_CLEAR -> QuietHours.clearDigest(context)
        }
    }
}
