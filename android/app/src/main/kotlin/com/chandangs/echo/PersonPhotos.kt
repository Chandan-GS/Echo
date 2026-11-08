package com.chandangs.echo

import android.app.Activity
import android.app.Notification
import android.app.Person
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.graphics.drawable.Icon
import android.media.ExifInterface
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.Parcelable
import android.os.ext.SdkExtensions
import android.provider.MediaStore
import android.service.notification.StatusBarNotification
import android.util.Log
import androidx.annotation.RequiresApi
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.nio.ByteBuffer
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/**
 * The decisions behind profile pictures, free of Android types so they can be
 * checked on a plain JVM (PersonPhotoRulesCheck.kt). [photoKey] must match
 * photoKey in person_photos.dart: both are pinned to
 * test/fixtures/photo_key_vectors.json.
 */
object PhotoRules {
    private val whitespace =
        Regex("[\\t-\\r \\u0085\\u00A0\\u1680\\u2000-\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000\\uFEFF]+")

    private const val FNV_OFFSET = -3750763034362895579L // 0xcbf29ce484222325
    private const val FNV_PRIME = 0x100000001b3L

    const val DAY_MS = 24 * 60 * 60 * 1000L

    /**
     * Trimmed, whitespace collapsed, lowercased one code point at a time.
     * String.lowercase() is avoided: it has context rules (final sigma) that
     * Dart doesn't, and the two sides have to agree. Only Latin, Greek and
     * Cyrillic capitals are lowered, since Dart's and Android's case tables
     * differ elsewhere. A lone surrogate becomes U+FFFD, which is what Dart's
     * UTF-8 encoder does with one.
     */
    fun normalise(s: String): String {
        var text = whitespace.replace(s, " ")
        if (text.startsWith(" ")) text = text.substring(1)
        if (text.endsWith(" ")) text = text.substring(0, text.length - 1)
        val out = StringBuilder(text.length)
        text.codePoints().forEach { cp ->
            out.appendCodePoint(
                when {
                    cp in 0xD800..0xDFFF -> 0xFFFD
                    cp in 0x41..0x24F || cp in 0x391..0x3A9 || cp in 0x400..0x42F -> Character.toLowerCase(cp)
                    else -> cp
                },
            )
        }
        return out.toString()
    }

    /** Null when [name] can't name one person: empty, or a "Sender · Group" line. */
    fun photoKey(name: String, source: String): String? {
        val n = normalise(name)
        val s = normalise(source)
        if (n.isEmpty() || s.isEmpty() || n.contains(" · ")) return null
        var hash = FNV_OFFSET
        for (b in (s + "\u0000" + n).toByteArray(Charsets.UTF_8)) {
            hash = (hash xor (b.toLong() and 0xff)) * FNV_PRIME
        }
        return java.lang.Long.toHexString(hash).padStart(16, '0')
    }

    class Sender<I : Any>(val name: String, val icon: I?)

    class Assignment<I : Any>(val name: String, val icon: I)

    /**
     * Whose picture each icon in a conversation is. A sender's own icon is
     * theirs. The notification's large icon is the chat's: in a group that's
     * the group's picture, so it goes under the group and never a sender, and
     * in a one-to-one chat it stands in for the other person's. [senders] are
     * oldest first; the owner never gets a picture from their own messages.
     */
    fun <I : Any> assign(
        isGroup: Boolean,
        title: String,
        selfName: String?,
        senders: List<Sender<I>>,
        largeIcon: I?,
    ): List<Assignment<I>> {
        val self = selfName?.let(::normalise)
        val group = normalise(title)
        val others = LinkedHashMap<String, Sender<I>>()
        for (s in senders) {
            val who = normalise(s.name)
            if (who.isEmpty() || who == self) continue
            // Would overwrite the group's own picture.
            if (isGroup && who == group) continue
            val had = others[who]
            others[who] = if (s.icon == null && had?.icon != null) had else s
        }
        val out = others.values.mapNotNull { s -> s.icon?.let { Assignment(s.name, it) } }.toMutableList()
        if (largeIcon == null) return out
        if (isGroup) {
            if (group.isNotEmpty()) out += Assignment(title, largeIcon)
            return out
        }
        // More than one sender means this isn't really one-to-one.
        val other = others.values.singleOrNull() ?: return out
        if (other.icon == null) out += Assignment(other.name, largeIcon)
        return out
    }

    /** Checked within the last day and the picture hasn't changed. */
    fun shouldSkip(lastHash: String?, lastCheckedAt: Long, hash: String, now: Long): Boolean =
        lastHash == hash && now - lastCheckedAt in 0 until DAY_MS

    enum class Shown { CHOSEN, DP, INITIALS }

    /** The owner's chosen photo, else their "use initials", else the DP. */
    fun shown(hasChosen: Boolean, useInitials: Boolean, hasDp: Boolean): Shown = when {
        hasChosen -> Shown.CHOSEN
        useInitials -> Shown.INITIALS
        hasDp -> Shown.DP
        else -> Shown.INITIALS
    }

    /** A package's own drawable, or the framework's: a logo, not a face. */
    fun isAppResource(resPackage: String?, postingPackage: String): Boolean =
        resPackage == null || resPackage == postingPackage || resPackage == "android"

    /** At most two colours on the sample grid: a placeholder, not a photo. */
    fun isFlat(argb: IntArray): Boolean {
        val colours = HashSet<Int>()
        for (c in argb) {
            colours += if (c ushr 24 < 16) 0 else (c and 0xF0F0F0) or (0xFF shl 24)
            if (colours.size > 2) return false
        }
        return true
    }

    /** Whether two equal-sized samples are the same picture, over white. */
    fun looksAlike(a: IntArray, b: IntArray): Boolean {
        if (a.size != b.size || a.isEmpty()) return false
        var total = 0L
        for (i in a.indices) {
            for (shift in intArrayOf(16, 8, 0)) {
                total += kotlin.math.abs(overWhite(a[i], shift) - overWhite(b[i], shift))
            }
        }
        return total / (a.size * 3) < 12
    }

    private fun overWhite(c: Int, shift: Int): Int {
        val alpha = c ushr 24
        val value = (c shr shift) and 0xFF
        return (value * alpha + 255 * (255 - alpha)) / 255
    }

    class Stored(val key: String, val files: Int, val chosen: Boolean, val updatedAt: Long)

    /** Rows to drop to get under [cap] files: DPs before chosen photos, oldest first. */
    fun evictions(rows: List<Stored>, cap: Int): List<String> {
        var over = rows.sumOf { it.files } - cap
        if (over <= 0) return emptyList()
        val out = mutableListOf<String>()
        for (row in rows.filter { it.files > 0 }.sortedWith(compareBy({ it.chosen }, { it.updatedAt }))) {
            if (over <= 0) break
            out += row.key
            over -= row.files
        }
        return out
    }
}

/**
 * Profile pictures, kept on the phone only: the DPs chat apps put on their
 * notifications, and the photo or "use initials" the owner picked instead.
 *
 * Everything lives in the no-backup files dir (never in a cloud backup or a
 * device transfer) and is touched only on [worker], so a photo problem can't
 * reach notification handling. Nothing here logs a name.
 */
object PersonPhotos {
    private const val TAG = "EchoPersonPhotos"
    private const val DIR = "person_photos"
    private const val INDEX = "index.json"
    private const val SIZE_PX = 144
    private const val SAMPLE_PX = 16
    private const val MAX_FILES = 500
    private const val MAX_QUEUED_CAPTURES = 64
    private const val PICK_REQUEST = 7403
    private const val PREFS = "echo_person_photos"
    private const val PREF_PENDING = "pending_pick"
    private const val KEY_SENDER_PERSON = "sender_person"

    private class Row(
        var dp: String? = null,
        var hash: String? = null,
        var checkedAt: Long = 0,
        var chosen: String? = null,
        var initials: Boolean = false,
        var pkg: String? = null,
        var updatedAt: Long = 0,
    ) {
        val files get() = (if (dp != null) 1 else 0) + (if (chosen != null) 1 else 0)
        val empty get() = dp == null && chosen == null && !initials
    }

    private class PendingPick(val keys: List<String>, val pkg: String?, val result: MethodChannel.Result?)

    private val worker = Executors.newSingleThreadExecutor { job ->
        Thread(job, "echo-person-photos").apply { priority = Thread.MIN_PRIORITY }
    }
    private val main = Handler(Looper.getMainLooper())
    private val queuedCaptures = AtomicInteger()

    @Volatile private var channel: MethodChannel? = null
    private var pendingPick: PendingPick? = null

    // Worker thread only, from here down.
    private var rows: MutableMap<String, Row>? = null
    private var dirty = false
    private var sweptAccess: String? = null
    private val logos = HashMap<String, IntArray?>()

    /** Lets Dart hear about photos that change while it's on screen. */
    fun attach(channel: MethodChannel) {
        this.channel = channel
    }

    /**
     * Called on the listener's thread for each chat notification Echo is
     * allowed to read. Only reads references here; decoding waits for [worker].
     */
    fun capture(
        context: Context,
        sbn: StatusBarNotification,
        conversation: ConversationReader.Conversation,
        source: String,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return
        try {
            val notification = sbn.notification ?: return
            val pkg = sbn.packageName ?: return
            val jobs = PhotoRules.assign(
                conversation.isGroup,
                conversation.title,
                conversation.selfName,
                senderIcons(notification),
                notification.getLargeIcon(),
            )
            if (jobs.isEmpty()) return
            // A burst of notifications shouldn't pile up bitmaps in memory.
            if (queuedCaptures.incrementAndGet() > MAX_QUEUED_CAPTURES) {
                queuedCaptures.decrementAndGet()
                return
            }
            val app = context.applicationContext
            worker.execute {
                try {
                    val changed = LinkedHashSet<String>()
                    sweep(app, changed)
                    val now = System.currentTimeMillis()
                    for (job in jobs) {
                        try {
                            store(app, pkg, source, job.name, job.icon, now, changed)
                        } catch (t: Throwable) {
                            Log.w(TAG, "Skipped a picture: ${t.javaClass.simpleName}")
                        }
                    }
                    enforceCap(app, changed)
                    finish(app, changed)
                } catch (t: Throwable) {
                    Log.w(TAG, "Capture failed: ${t.javaClass.simpleName}")
                } finally {
                    queuedCaptures.decrementAndGet()
                }
            }
        } catch (t: Throwable) {
            Log.w(TAG, "Couldn't read pictures: ${t.javaClass.simpleName}")
        }
    }

    @RequiresApi(Build.VERSION_CODES.P)
    private fun senderIcons(notification: Notification): List<PhotoRules.Sender<Icon>> {
        @Suppress("DEPRECATION")
        val raw = notification.extras?.getParcelableArray(Notification.EXTRA_MESSAGES) ?: return emptyList()
        // Oldest first, as PhotoRules.assign expects.
        return raw.mapNotNull { it as? Bundle }
            .sortedBy { it.getLong("time", 0L) }
            .mapNotNull { message ->
                @Suppress("DEPRECATION")
                val person = message.getParcelable<Parcelable>(KEY_SENDER_PERSON) as? Person
                val name = person?.name?.toString()?.trim()?.takeIf { it.isNotEmpty() } ?: return@mapNotNull null
                PhotoRules.Sender(name, person.icon)
            }
    }

    @RequiresApi(Build.VERSION_CODES.P)
    private fun store(
        context: Context,
        pkg: String,
        source: String,
        name: String,
        icon: Icon,
        now: Long,
        changed: MutableSet<String>,
    ) {
        val key = PhotoRules.photoKey(name, source) ?: return
        // Switched off between being queued and getting here.
        if (!AppAccessRules.hears(context, pkg)) return
        val table = rows(context)
        val row = table[key]
        val isUri = icon.type == Icon.TYPE_URI || icon.type == Icon.TYPE_URI_ADAPTIVE_BITMAP
        if (icon.type == Icon.TYPE_RESOURCE && PhotoRules.isAppResource(icon.resPackage, pkg)) return

        // A URI can be judged before it's opened; anything else by its pixels.
        val uriHash = if (isUri) {
            if (icon.uri.scheme != "content") return
            hashOf(icon.uri.toString().toByteArray())
        } else {
            null
        }
        if (uriHash != null && PhotoRules.shouldSkip(row?.hash, row?.checkedAt ?: 0, uriHash, now)) return

        val square = (if (isUri) decodeUri(context, icon.uri)?.let(::cropAndRecycle) else draw(icon.loadDrawable(context)))
            ?: return
        try {
            val sample = sample(square)
            if (PhotoRules.isFlat(sample)) return
            if (logoOf(context, pkg)?.let { PhotoRules.looksAlike(it, sample) } == true) return

            val pixels = hashOf(square)
            val hash = uriHash ?: pixels
            if (PhotoRules.shouldSkip(row?.hash, row?.checkedAt ?: 0, hash, now)) return

            val target = row ?: Row().also { table[key] = it }
            target.pkg = pkg
            target.hash = hash
            target.checkedAt = now
            target.updatedAt = now
            dirty = true

            val fileName = "$key.d.${pixels.take(8)}.webp"
            if (target.dp == fileName && File(dir(context), fileName).exists()) return
            write(context, square, fileName)
            target.dp?.takeIf { it != fileName }?.let { File(dir(context), it).delete() }
            target.dp = fileName
            changed += key
        } finally {
            square.recycle()
        }
    }

    /** Deletes the pictures of apps the owner has just switched off. */
    private fun sweep(context: Context, changed: MutableSet<String>) {
        val access = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getString("flutter.app_access", null)
        if (access == sweptAccess) return
        sweptAccess = access
        val table = rows(context)
        for ((key, row) in table.entries.toList()) {
            val pkg = row.pkg ?: continue
            if (!AppAccessRules.hears(context, pkg)) drop(context, table, key, changed)
        }
    }

    private fun enforceCap(context: Context, changed: MutableSet<String>) {
        val table = rows(context)
        val stored = table.map { (key, row) ->
            PhotoRules.Stored(key, row.files, row.chosen != null, row.updatedAt)
        }
        for (key in PhotoRules.evictions(stored, MAX_FILES)) drop(context, table, key, changed)
    }

    private fun drop(context: Context, table: MutableMap<String, Row>, key: String, changed: MutableSet<String>) {
        val row = table.remove(key) ?: return
        row.dp?.let { File(dir(context), it).delete() }
        row.chosen?.let { File(dir(context), it).delete() }
        dirty = true
        changed += key
    }

    /** Saves the index if anything moved, then tells Dart what did. */
    private fun finish(context: Context, changed: Set<String>) {
        if (dirty) {
            dirty = false
            saveIndex(context)
        }
        if (changed.isNotEmpty()) {
            val keys = changed.toList()
            main.post {
                try {
                    channel?.invokeMethod("changed", keys)
                } catch (t: Throwable) {
                    Log.w(TAG, "Dart wasn't listening: ${t.javaClass.simpleName}")
                }
            }
        }
    }

    // Dart's calls.

    fun handle(activity: Activity, call: MethodCall, result: MethodChannel.Result) {
        val app = activity.applicationContext
        when (call.method) {
            "resolveAll" -> {
                val items = call.argument<List<Map<String, Any?>>>("items") ?: emptyList()
                onWorker(result, emptyMap<String, Any>()) {
                    val changed = LinkedHashSet<String>()
                    sweep(app, changed)
                    val out = items.associate { item ->
                        @Suppress("UNCHECKED_CAST")
                        (item["id"] as String) to resolve(app, item["keys"] as List<String>)
                    }
                    finish(app, changed)
                    out
                }
            }
            "choose" -> startPick(
                activity,
                call.argument<List<String>>("keys") ?: emptyList(),
                call.argument<String>("package"),
                result,
            )
            "useInitials" -> {
                val keys = call.argument<List<String>>("keys") ?: emptyList()
                val pkg = call.argument<String>("package")
                onWorker(result, false) {
                    setOverride(app, keys, pkg, chosen = null, initials = true)
                    true
                }
            }
            "reset" -> {
                val keys = call.argument<List<String>>("keys") ?: emptyList()
                onWorker(result, false) {
                    setOverride(app, keys, null, chosen = null, initials = false)
                    true
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun onWorker(result: MethodChannel.Result, fallback: Any, job: () -> Any) {
        worker.execute {
            val out = try {
                job()
            } catch (t: Throwable) {
                Log.w(TAG, "Call failed: ${t.javaClass.simpleName}")
                fallback
            }
            main.post { result.success(out) }
        }
    }

    private fun resolve(context: Context, keys: List<String>): Map<String, Any?> {
        val table = rows(context)
        val found = keys.mapNotNull { table[it] }
        val chosen = found.firstNotNullOfOrNull { row -> row.chosen?.let { existing(context, it) } }
        val dp = found.firstNotNullOfOrNull { row -> row.dp?.let { existing(context, it) } }
        val initials = found.any { it.initials }
        return when (PhotoRules.shown(chosen != null, initials, dp != null)) {
            PhotoRules.Shown.CHOSEN -> mapOf("path" to chosen, "choice" to "chosen", "hasDp" to (dp != null))
            PhotoRules.Shown.DP -> mapOf("path" to dp, "choice" to "auto", "hasDp" to true)
            PhotoRules.Shown.INITIALS -> mapOf(
                "path" to null,
                "choice" to if (initials) "initials" else "auto",
                "hasDp" to (dp != null),
            )
        }
    }

    private fun existing(context: Context, fileName: String): String? =
        File(dir(context), fileName).takeIf { it.exists() }?.absolutePath

    private fun setOverride(
        context: Context,
        keys: List<String>,
        pkg: String?,
        chosen: Bitmap?,
        initials: Boolean,
    ) {
        val table = rows(context)
        val changed = LinkedHashSet<String>()
        val now = System.currentTimeMillis()
        for (key in keys) {
            val row = table[key] ?: Row().also { table[key] = it }
            var fileName: String? = null
            if (chosen != null) {
                fileName = "$key.c.${hashOf(chosen).take(8)}.webp"
                write(context, chosen, fileName)
            }
            row.chosen?.takeIf { it != fileName }?.let { File(dir(context), it).delete() }
            row.chosen = fileName
            row.initials = initials
            if (pkg != null) row.pkg = pkg
            row.updatedAt = now
            if (row.empty) table.remove(key)
            dirty = true
            changed += key
        }
        enforceCap(context, changed)
        finish(context, changed)
    }

    // The system photo picker. It needs no permission: the picked file is
    // readable until this activity finishes, so it's copied straight away.

    private fun startPick(activity: Activity, keys: List<String>, pkg: String?, result: MethodChannel.Result) {
        if (keys.isEmpty()) {
            result.success("unreadable")
            return
        }
        if (pendingPick != null) {
            result.success("busy")
            return
        }
        pendingPick = PendingPick(keys, pkg, result)
        // The activity can be killed behind the picker; this brings the pick back.
        activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(PREF_PENDING, JSONObject().put("keys", org.json.JSONArray(keys)).put("package", pkg).toString())
            .apply()
        val intents = buildList {
            if (hasSystemPicker()) add(Intent(MediaStore.ACTION_PICK_IMAGES).setType("image/*"))
            add(Intent(Intent.ACTION_GET_CONTENT).setType("image/*").addCategory(Intent.CATEGORY_OPENABLE))
        }
        for (intent in intents) {
            try {
                activity.startActivityForResult(intent, PICK_REQUEST)
                return
            } catch (e: ActivityNotFoundException) {
                continue
            } catch (t: Throwable) {
                Log.w(TAG, "Picker failed: ${t.javaClass.simpleName}")
            }
        }
        pendingPick = null
        clearPending(activity)
        result.success("unavailable")
    }

    private fun hasSystemPicker(): Boolean = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU -> true
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.R -> SdkExtensions.getExtensionVersion(Build.VERSION_CODES.R) >= 2
        else -> false
    }

    /** True when [requestCode] was the picker's. */
    fun onPickResult(context: Context, requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_REQUEST) return false
        val app = context.applicationContext
        val pending = pendingPick ?: restorePending(app)
        pendingPick = null
        clearPending(app)
        if (pending == null) return true
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            replyTo(pending, "cancel")
            return true
        }
        worker.execute {
            val outcome = try {
                val picked = if (uri.scheme == "content") decodeUri(app, uri) else null
                if (picked == null) {
                    "unreadable"
                } else {
                    val square = cropAndRecycle(picked)
                    try {
                        setOverride(app, pending.keys, pending.pkg, chosen = square, initials = false)
                    } finally {
                        square.recycle()
                    }
                    "ok"
                }
            } catch (t: Throwable) {
                // Includes an image too big to decode.
                Log.w(TAG, "Couldn't use that photo: ${t.javaClass.simpleName}")
                "unreadable"
            }
            replyTo(pending, outcome)
        }
        return true
    }

    private fun replyTo(pending: PendingPick, outcome: String) {
        main.post {
            try {
                pending.result?.success(outcome)
            } catch (t: Throwable) {
                Log.w(TAG, "Dart wasn't waiting: ${t.javaClass.simpleName}")
            }
        }
    }

    private fun restorePending(context: Context): PendingPick? = try {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(PREF_PENDING, null)
        raw?.let {
            val json = JSONObject(it)
            val keys = json.getJSONArray("keys")
            PendingPick(
                (0 until keys.length()).map { i -> keys.getString(i) },
                if (json.isNull("package")) null else json.getString("package"),
                null,
            )
        }
    } catch (e: Exception) {
        null
    }

    private fun clearPending(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(PREF_PENDING).apply()
    }

    // Bitmaps.

    /** Decodes no more of [uri] than the avatar needs. Throws if it can't be read. */
    private fun decodeUri(context: Context, uri: Uri): Bitmap? {
        val resolver = context.contentResolver
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) } ?: return null
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sampleSize = 1
        while (minOf(bounds.outWidth, bounds.outHeight) / (sampleSize * 2) >= SIZE_PX) sampleSize *= 2
        val options = BitmapFactory.Options().apply {
            inSampleSize = sampleSize
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val decoded = resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, options) }
            ?: return null
        val degrees = try {
            resolver.openInputStream(uri)?.use {
                when (ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                    ExifInterface.ORIENTATION_ROTATE_90 -> 90
                    ExifInterface.ORIENTATION_ROTATE_180 -> 180
                    ExifInterface.ORIENTATION_ROTATE_270 -> 270
                    else -> 0
                }
            } ?: 0
        } catch (e: Exception) {
            0
        }
        if (degrees == 0) return decoded
        val rotated = Bitmap.createBitmap(
            decoded, 0, 0, decoded.width, decoded.height,
            Matrix().apply { postRotate(degrees.toFloat()) }, true,
        )
        if (rotated !== decoded) decoded.recycle()
        return rotated
    }

    private fun draw(drawable: Drawable?): Bitmap? {
        if (drawable == null) return null
        if (drawable is BitmapDrawable) return drawable.bitmap?.let(::crop)
        val out = Bitmap.createBitmap(SIZE_PX, SIZE_PX, Bitmap.Config.ARGB_8888)
        drawable.setBounds(0, 0, SIZE_PX, SIZE_PX)
        // On white, so the initials under the avatar can't show through.
        drawable.draw(Canvas(out).apply { drawColor(Color.WHITE) })
        return out
    }

    private fun cropAndRecycle(source: Bitmap): Bitmap {
        val out = crop(source)
        source.recycle()
        return out
    }

    private fun crop(source: Bitmap): Bitmap {
        val side = minOf(source.width, source.height)
        val left = (source.width - side) / 2
        val top = (source.height - side) / 2
        val out = Bitmap.createBitmap(SIZE_PX, SIZE_PX, Bitmap.Config.ARGB_8888)
        Canvas(out).apply { drawColor(Color.WHITE) }.drawBitmap(
            source,
            Rect(left, top, left + side, top + side),
            Rect(0, 0, SIZE_PX, SIZE_PX),
            Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG),
        )
        return out
    }

    private fun sample(bitmap: Bitmap): IntArray {
        val small = Bitmap.createScaledBitmap(bitmap, SAMPLE_PX, SAMPLE_PX, true)
        val pixels = IntArray(SAMPLE_PX * SAMPLE_PX)
        small.getPixels(pixels, 0, SAMPLE_PX, 0, 0, SAMPLE_PX, SAMPLE_PX)
        if (small !== bitmap) small.recycle()
        return pixels
    }

    private fun logoOf(context: Context, pkg: String): IntArray? {
        if (logos.containsKey(pkg)) return logos[pkg]
        val logo = try {
            val drawable = context.packageManager.getApplicationIcon(pkg)
            val bitmap = Bitmap.createBitmap(SIZE_PX, SIZE_PX, Bitmap.Config.ARGB_8888)
            drawable.setBounds(0, 0, SIZE_PX, SIZE_PX)
            drawable.draw(Canvas(bitmap))
            sample(bitmap).also { bitmap.recycle() }
        } catch (e: Exception) {
            null
        }
        logos[pkg] = logo
        return logo
    }

    private fun hashOf(bitmap: Bitmap): String {
        val buffer = ByteBuffer.allocate(bitmap.byteCount)
        bitmap.copyPixelsToBuffer(buffer)
        return hashOf(buffer.array())
    }

    private fun hashOf(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes)
            .take(8).joinToString("") { "%02x".format(it) }

    private fun write(context: Context, bitmap: Bitmap, fileName: String) {
        val folder = dir(context)
        val temp = File(folder, "$fileName.tmp")
        temp.outputStream().use { out ->
            @Suppress("DEPRECATION")
            val format = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) Bitmap.CompressFormat.WEBP_LOSSY else Bitmap.CompressFormat.WEBP
            check(bitmap.compress(format, 85, out)) { "encode failed" }
        }
        val target = File(folder, fileName)
        if (!temp.renameTo(target)) {
            temp.delete()
            error("rename failed")
        }
    }

    // The index: which files belong to whom.

    private fun dir(context: Context): File =
        File(context.noBackupFilesDir, DIR).apply { mkdirs() }

    private fun rows(context: Context): MutableMap<String, Row> {
        rows?.let { return it }
        val table = HashMap<String, Row>()
        val folder = dir(context)
        try {
            val json = JSONObject(File(folder, INDEX).readText())
            for (key in json.keys()) {
                val o = json.getJSONObject(key)
                table[key] = Row(
                    dp = o.optString("d").ifEmpty { null },
                    hash = o.optString("h").ifEmpty { null },
                    checkedAt = o.optLong("c"),
                    chosen = o.optString("x").ifEmpty { null },
                    initials = o.optBoolean("i"),
                    pkg = o.optString("p").ifEmpty { null },
                    updatedAt = o.optLong("u"),
                )
            }
        } catch (e: Exception) {
            // First run, or a damaged index: the pictures come back with the next notifications.
        }
        // Anything the index doesn't name is left over from an interrupted write.
        val named = table.values.flatMap { listOfNotNull(it.dp, it.chosen) }.toHashSet()
        folder.listFiles()?.forEach { file ->
            if (file.name != INDEX && file.name !in named) file.delete()
        }
        rows = table
        return table
    }

    private fun saveIndex(context: Context) {
        val json = JSONObject()
        rows(context).forEach { (key, row) ->
            json.put(
                key,
                JSONObject()
                    .put("d", row.dp ?: "")
                    .put("h", row.hash ?: "")
                    .put("c", row.checkedAt)
                    .put("x", row.chosen ?: "")
                    .put("i", row.initials)
                    .put("p", row.pkg ?: "")
                    .put("u", row.updatedAt),
            )
        }
        val folder = dir(context)
        val temp = File(folder, "$INDEX.tmp")
        temp.writeText(json.toString())
        if (!temp.renameTo(File(folder, INDEX))) temp.delete()
    }
}
