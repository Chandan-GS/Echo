package com.chandangs.echo

import android.app.ActivityOptions
import android.app.Notification
import android.app.PendingIntent
import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.provider.ContactsContract
import org.json.JSONObject

/**
 * How Echo answers and opens chats, best way first:
 *
 * 1. Through the chat notification's own Reply button, the way a smartwatch
 *    answers: Echo sends the reply, from the owner's account, by the chat app.
 * 2. For WhatsApp, by the chat's own id: Echo writes the reply into exactly
 *    that chat, group or one-to-one, and the owner taps send.
 * 3. Through the app's own "send to" list, with the reply written in, when
 *    the chat's id isn't known.
 *
 * Notification buttons can't be stored, so they're kept in memory for six
 * hours. WhatsApp chat ids are kept on the phone only (never synced).
 */
object ReplyActions {
    private const val KEEP_MS = 6 * 60 * 60 * 1000L
    private const val MAX_THREADS = 100
    private const val MAX_CHAT_IDS = 400
    private const val WHATSAPP_PROFILE = "vnd.android.cursor.item/vnd.com.whatsapp.profile"

    private class Saved(val reply: Notification.Action?, val open: PendingIntent?, val at: Long)

    private val byThread = LinkedHashMap<String, Saved>()

    @Synchronized
    fun remember(
        context: Context,
        thread: String,
        conversation: ConversationReader.Conversation,
        notification: Notification,
    ) {
        conversation.chatId?.let { rememberChatId(context, thread, it) }
        val reply = replyAction(notification)
        val open = notification.contentIntent
        if (reply == null && open == null) return
        byThread.remove(thread)
        byThread[thread] = Saved(reply, open, System.currentTimeMillis())
        while (byThread.size > MAX_THREADS) byThread.remove(byThread.keys.first())
    }

    /**
     * How a reply in [thread] would go right now: "send" (Echo sends it),
     * "write" (Echo writes it into the chat), "pick" (into the app's "send
     * to" list), or "copy" (only the chat app can be opened).
     */
    @Synchronized
    fun route(context: Context, thread: String): String = when {
        fresh(thread)?.reply != null -> "send"
        isWhatsApp(thread) && chatId(context, thread) != null -> "write"
        isWhatsApp(thread) -> "pick"
        fresh(thread)?.open != null -> "copy"
        else -> "pick"
    }

    /** True once the chat app has been handed [text] through the notification. */
    @Synchronized
    fun send(context: Context, thread: String, text: String): Boolean {
        val action = fresh(thread)?.reply ?: return false
        val inputs = action.remoteInputs?.filter { it.allowFreeFormInput }?.toTypedArray()
        if (inputs.isNullOrEmpty()) return false
        val results = Bundle().apply { inputs.forEach { putCharSequence(it.resultKey, text) } }
        val intent = Intent().addFlags(Intent.FLAG_RECEIVER_FOREGROUND)
        RemoteInput.addResultsToIntent(inputs, intent, results)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            RemoteInput.setResultsSource(intent, RemoteInput.SOURCE_FREE_FORM_INPUT)
        }
        return try {
            action.actionIntent.send(context, 0, intent)
            true
        } catch (e: PendingIntent.CanceledException) {
            false
        }
    }

    /**
     * Writes [text] into [thread]'s chat for the owner to send. Returns
     * "written" (that chat opened with it), "picker" (the app's "send to"
     * list opened with it), "opened" (the chat opened; the caller copied the
     * text), or null when nothing could be opened.
     */
    @Synchronized
    fun write(context: Context, thread: String, text: String): String? {
        val app = appOf(thread)
        val chatId = if (isWhatsApp(thread)) chatId(context, thread) else null
        if (chatId != null) {
            val intoChat = share(app, text).putExtra("jid", chatId)
            if (start(context, intoChat)) return "written"
        }
        if (!isWhatsApp(thread)) {
            fresh(thread)?.open?.let { if (sendOpen(context, it)) return "opened" }
        }
        return if (start(context, share(app, text))) "picker" else null
    }

    /** Opens [thread]'s chat itself, as tapping its notification would. */
    @Synchronized
    fun openChat(context: Context, thread: String): Boolean {
        val chatId = if (isWhatsApp(thread)) chatId(context, thread) else null
        if (chatId != null) {
            val chat = Intent().setClassName(appOf(thread), "com.whatsapp.Conversation")
                .putExtra("jid", chatId)
            if (start(context, chat)) return true
        }
        return fresh(thread)?.open?.let { sendOpen(context, it) } ?: false
    }

    /**
     * Opens [thread]'s chat with [text] typed in it (WhatsApp, by the chat's
     * id), or the app's "send to" list with it. For a reply written on a
     * paired computer, which the owner sends from the phone.
     */
    @Synchronized
    fun writeIntent(context: Context, thread: String, text: String): Intent {
        val chatId = if (isWhatsApp(thread)) chatId(context, thread) else null
        val intent = share(appOf(thread), text)
        if (chatId != null) intent.putExtra("jid", chatId)
        return intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    /**
     * What a reminder's "Open chat" button opens: [thread]'s chat itself, or
     * the chat app's own tap target while its notification is fresh. Null
     * when neither is known.
     */
    @Synchronized
    fun openChatIntent(context: Context, thread: String, requestCode: Int): PendingIntent? {
        val chatId = if (isWhatsApp(thread)) chatId(context, thread) else null
        if (chatId != null) {
            val chat = Intent().setClassName(appOf(thread), "com.whatsapp.Conversation")
                .putExtra("jid", chatId)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            return PendingIntent.getActivity(context, requestCode, chat, PendingIntent.FLAG_IMMUTABLE)
        }
        return fresh(thread)?.open
    }

    private fun share(app: String, text: String) = Intent(Intent.ACTION_SEND)
        .setType("text/plain")
        .setPackage(app)
        .putExtra(Intent.EXTRA_TEXT, text)

    private fun start(context: Context, intent: Intent): Boolean = try {
        context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (e: Exception) {
        false // not installed, or not allowed
    }

    private fun sendOpen(context: Context, open: PendingIntent): Boolean {
        // Since Android 14 the app sending another app's tap target has to say
        // it may open a screen; Echo is on screen when the owner asks for this.
        val options = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ActivityOptions.makeBasic()
                .setPendingIntentBackgroundActivityStartMode(ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED)
                .toBundle()
        } else {
            null
        }
        return try {
            open.send(context, 0, null, null, null, null, options)
            true
        } catch (e: PendingIntent.CanceledException) {
            false
        }
    }

    private fun fresh(thread: String): Saved? {
        val saved = byThread[thread] ?: return null
        if (System.currentTimeMillis() - saved.at <= KEEP_MS) return saved
        byThread.remove(thread)
        return null
    }

    private fun replyAction(n: Notification): Notification.Action? {
        fun takesText(a: Notification.Action) = a.remoteInputs?.any { it.allowFreeFormInput } == true
        val actions = n.actions.orEmpty().filter(::takesText)
        val marked = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            actions.firstOrNull { it.semanticAction == Notification.Action.SEMANTIC_ACTION_REPLY }
        } else {
            null
        }
        return marked
            ?: actions.firstOrNull()
            ?: Notification.WearableExtender(n).actions.firstOrNull(::takesText)
    }

    private fun appOf(thread: String) = thread.substringBeforeLast(':')

    private fun isWhatsApp(thread: String) =
        appOf(thread).let { it == "com.whatsapp" || it == "com.whatsapp.w4b" }

    // ── Chat ids: thread → WhatsApp's id for the chat, on the phone only ─────

    /**
     * WhatsApp's id for [thread]'s chat. Kept from its notifications; for a
     * one-to-one chat seen before ids were kept, found among the WhatsApp
     * entries in the owner's contacts (when Echo may read them) by matching
     * the thread's own fingerprint, so it's exactly that chat.
     */
    private fun chatId(context: Context, thread: String): String? {
        chatIds(context).optString(thread).takeIf { it.isNotEmpty() }?.let { return it }
        val found = whatsappContactIds(context).firstOrNull {
            "${appOf(thread)}:${ConversationReader.shortHash(it)}" == thread
        } ?: return null
        rememberChatId(context, thread, found)
        return found
    }

    private fun whatsappContactIds(context: Context): List<String> = try {
        context.contentResolver.query(
            ContactsContract.Data.CONTENT_URI,
            arrayOf(ContactsContract.Data.DATA1),
            "${ContactsContract.Data.MIMETYPE} = ?",
            arrayOf(WHATSAPP_PROFILE),
            null,
        )?.use { c -> buildList { while (c.moveToNext()) c.getString(0)?.let(::add) } } ?: emptyList()
    } catch (e: SecurityException) {
        emptyList() // contacts not allowed
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences("echo_chat_ids", Context.MODE_PRIVATE)

    private fun chatIds(context: Context): JSONObject = try {
        JSONObject(prefs(context).getString("ids", "{}") ?: "{}")
    } catch (e: Exception) {
        JSONObject()
    }

    private fun rememberChatId(context: Context, thread: String, chatId: String) {
        val ids = chatIds(context)
        if (ids.optString(thread) == chatId) return
        ids.remove(thread)
        ids.put(thread, chatId)
        while (ids.length() > MAX_CHAT_IDS) ids.remove(ids.keys().next())
        prefs(context).edit().putString("ids", ids.toString()).apply()
    }
}
