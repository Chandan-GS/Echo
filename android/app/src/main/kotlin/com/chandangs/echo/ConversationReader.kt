package com.chandangs.echo

import android.app.Notification
import android.app.Person
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.os.Parcelable
import android.service.notification.StatusBarNotification
import org.json.JSONObject
import java.security.MessageDigest

/**
 * Reads chat notifications as conversations rather than preview lines.
 *
 * Messaging apps (WhatsApp, Telegram, Signal, Google Messages, Slack…) post
 * MessagingStyle notifications: the last few messages of the thread, each with
 * its own sender and time, plus whether it's a group and who "you" are. The
 * plain title/text pair that the rest of the listener reads is only the newest
 * line, flattened. Everything here comes from documented Notification extras.
 */
object ConversationReader {

    data class Message(val sender: String?, val text: String, val time: Long)

    data class Conversation(
        /** Stable id for the thread, hashed so raw chat ids (phone numbers) never leave this device. */
        val thread: String,
        /** Group name, or the other person's name in a one-to-one chat. */
        val title: String,
        val isGroup: Boolean,
        /** How the app names the phone's owner, when it says. */
        val selfName: String?,
        /** Oldest first. A null sender is the phone's owner. */
        val messages: List<Message>,
    )

    // Notification.MessagingStyle.Message bundle keys.
    private const val KEY_TEXT = "text"
    private const val KEY_TIME = "time"
    private const val KEY_SENDER = "sender"
    private const val KEY_SENDER_PERSON = "sender_person"

    /** "College gang (3 messages)" / "College gang: 3 new messages" → "College gang". */
    private val countSuffix = Regex("""\s*(\(\d+ (new )?messages?\)|:\s*\d+ new messages?)$""", RegexOption.IGNORE_CASE)

    fun read(sbn: StatusBarNotification): Conversation? {
        val n = sbn.notification ?: return null
        val extras = n.extras ?: return null
        val raw = extras.getParcelableArray(Notification.EXTRA_MESSAGES) ?: return null
        val messages = raw.mapNotNull { (it as? Bundle)?.let(::message) }
            .sortedBy { it.time }
        if (messages.isEmpty()) return null

        val conversationTitle = extras.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE)
            ?.toString()?.replace(countSuffix, "")?.trim()?.takeIf { it.isNotEmpty() }
        // Before Android 9 a conversation title was how a group was signalled.
        val isGroup = if (extras.containsKey(Notification.EXTRA_IS_GROUP_CONVERSATION)) {
            extras.getBoolean(Notification.EXTRA_IS_GROUP_CONVERSATION)
        } else {
            conversationTitle != null
        }
        val title = conversationTitle
            ?: extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim()
            ?: messages.lastOrNull { it.sender != null }?.sender
            ?: ""

        return Conversation(
            thread = threadId(sbn, conversationTitle ?: title),
            title = title,
            isGroup = isGroup,
            selfName = selfName(extras),
            messages = messages,
        )
    }

    /** The same thread id for a notification of any style, so taps and swipes line up with messages. */
    fun threadId(sbn: StatusBarNotification, fallbackTitle: String? = null): String {
        val n = sbn.notification
        val conversationKey = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) n?.shortcutId else null)
            ?: n?.extras?.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE)?.toString()?.replace(countSuffix, "")?.trim()
            ?: fallbackTitle
            ?: n?.extras?.getCharSequence(Notification.EXTRA_TITLE)?.toString()
            ?: sbn.tag
            ?: sbn.id.toString()
        return "${sbn.packageName}:${shortHash(conversationKey)}"
    }

    private fun message(b: Bundle): Message? {
        val text = b.getCharSequence(KEY_TEXT)?.toString()?.trim().orEmpty()
        if (text.isEmpty()) return null
        val person: String? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            @Suppress("DEPRECATION")
            (b.getParcelable<Parcelable>(KEY_SENDER_PERSON) as? Person)?.name?.toString()
        } else {
            null
        }
        val sender = (person ?: b.getCharSequence(KEY_SENDER)?.toString())?.trim()?.takeIf { it.isNotEmpty() }
        return Message(sender, text, b.getLong(KEY_TIME, System.currentTimeMillis()))
    }

    private fun selfName(extras: Bundle): String? {
        val person: String? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            @Suppress("DEPRECATION")
            (extras.getParcelable<Parcelable>(Notification.EXTRA_MESSAGING_PERSON) as? Person)?.name?.toString()
        } else {
            null
        }
        return (person ?: extras.getCharSequence(Notification.EXTRA_SELF_DISPLAY_NAME)?.toString())
            ?.trim()?.takeIf { it.isNotEmpty() }
    }

    private fun shortHash(s: String): String =
        MessageDigest.getInstance("SHA-256").digest(s.toByteArray())
            .take(8).joinToString("") { "%02x".format(it) }

    /**
     * Which messages of a repost are new. Apps repost the whole recent thread
     * with every message, so each thread remembers the time of the newest
     * message already passed on. Kept in prefs: the listener can be restarted
     * at any time.
     */
    class Seen(context: Context) {
        private val prefs = context.getSharedPreferences("echo_conversations", Context.MODE_PRIVATE)
        private val seen: JSONObject = try {
            JSONObject(prefs.getString(KEY, "{}") ?: "{}")
        } catch (e: Exception) {
            JSONObject()
        }

        fun unseen(c: Conversation, now: Long): List<Message> {
            // A thread seen for the first time only passes on the last day,
            // not whatever history the app chose to include.
            val after = if (seen.has(c.thread)) seen.getLong(c.thread) else now - DAY_MS
            return c.messages.filter { it.time > after }
        }

        fun markSeen(c: Conversation) {
            val newest = c.messages.maxOf { it.time }
            if (seen.optLong(c.thread, 0L) >= newest) return
            seen.put(c.thread, newest)
            if (seen.length() > MAX_THREADS) prune()
            prefs.edit().putString(KEY, seen.toString()).apply()
        }

        private fun prune() {
            val oldest = seen.keys().asSequence().toList()
                .sortedBy { seen.getLong(it) }
                .take(seen.length() - MAX_THREADS)
            oldest.forEach { seen.remove(it) }
        }

        companion object {
            private const val KEY = "seen_v1"
            private const val MAX_THREADS = 400
            private const val DAY_MS = 24 * 60 * 60 * 1000L
        }
    }
}
