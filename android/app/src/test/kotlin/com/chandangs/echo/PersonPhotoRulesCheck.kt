package com.chandangs.echo

import java.io.File
import org.json.JSONArray

/**
 * Checks PhotoRules on a plain JVM (no Android, no JUnit): compile with
 * PersonPhotos.kt and android.jar on the classpath and run main, passing
 * test/fixtures/photo_key_vectors.json.
 */
fun main(args: Array<String>) {
    fun check(ok: Boolean, what: String) {
        if (!ok) throw AssertionError(what)
    }

    val vectors = JSONArray(File(args[0]).readText())
    check(vectors.length() > 10, "vectors present")
    for (i in 0 until vectors.length()) {
        val v = vectors.getJSONObject(i)
        val key = if (v.isNull("key")) null else v.getString("key")
        check(PhotoRules.photoKey(v.getString("name"), v.getString("source")) == key, "vector $i: ${v.getString("name")}")
    }

    val rahul = PhotoRules.Sender("Rahul", "rahul-face")
    val priya = PhotoRules.Sender("Priya", null as String?)

    fun names(list: List<PhotoRules.Assignment<String>>) = list.map { it.name to it.icon }

    check(
        names(PhotoRules.assign(true, "College gang", null, listOf(rahul, priya), "group-pic")) ==
            listOf("Rahul" to "rahul-face", "College gang" to "group-pic"),
        "group: large icon goes to the group, sender keeps their own",
    )
    check(
        names(PhotoRules.assign(true, "College gang", null, listOf(priya), "group-pic")) ==
            listOf("College gang" to "group-pic"),
        "group: a sender with no icon never gets the group's",
    )
    check(
        names(PhotoRules.assign(false, "Priya", null, listOf(priya), "large")) == listOf("Priya" to "large"),
        "one-to-one: large icon stands in",
    )
    check(
        names(PhotoRules.assign(false, "Rahul", null, listOf(rahul), "large")) == listOf("Rahul" to "rahul-face"),
        "one-to-one: the sender's own icon wins",
    )
    check(
        names(PhotoRules.assign(false, "Chat", null, listOf(rahul, priya), "large")) ==
            listOf("Rahul" to "rahul-face"),
        "two senders is not one-to-one",
    )
    check(
        names(PhotoRules.assign(false, "Priya", "Me", listOf(PhotoRules.Sender("me", "my-face"), priya), "large")) ==
            listOf("Priya" to "large"),
        "the owner's own icon is never stored",
    )
    check(
        names(PhotoRules.assign(true, "College gang", null, listOf(PhotoRules.Sender("College Gang", "x")), null)).isEmpty(),
        "a sender named like the group can't overwrite it",
    )
    check(
        PhotoRules.assign(false, "Priya", null, emptyList<PhotoRules.Sender<String>>(), "large").isEmpty(),
        "no sender, nobody to file it under",
    )
    check(
        names(PhotoRules.assign(false, "R", null, listOf(rahul, PhotoRules.Sender("Rahul", null as String?)), null)) ==
            listOf("Rahul" to "rahul-face"),
        "a newer message with no icon keeps the older icon",
    )

    val now = 10 * PhotoRules.DAY_MS
    check(PhotoRules.shouldSkip("h", now - 1000, "h", now), "same hash within a day skips")
    check(!PhotoRules.shouldSkip("h", now - PhotoRules.DAY_MS, "h", now), "a day later it re-checks")
    check(!PhotoRules.shouldSkip("h", now - 1000, "i", now), "a changed picture never skips")
    check(!PhotoRules.shouldSkip(null, now - 1000, "h", now), "first sighting never skips")
    check(!PhotoRules.shouldSkip("h", now + 5000, "h", now), "a clock moved back re-checks")

    check(PhotoRules.shown(true, true, true) == PhotoRules.Shown.CHOSEN, "chosen beats everything")
    check(PhotoRules.shown(false, true, true) == PhotoRules.Shown.INITIALS, "use initials beats the DP")
    check(PhotoRules.shown(false, false, true) == PhotoRules.Shown.DP, "DP beats default")
    check(PhotoRules.shown(false, false, false) == PhotoRules.Shown.INITIALS, "nothing means initials")

    check(PhotoRules.isAppResource("com.whatsapp", "com.whatsapp"), "own resource is a logo")
    check(PhotoRules.isAppResource("android", "com.whatsapp"), "framework default is a logo")
    check(!PhotoRules.isAppResource("com.other", "com.whatsapp"), "another package's resource isn't")

    val grey = IntArray(64) { 0xFF888888.toInt() }
    val silhouette = IntArray(64) { if (it % 2 == 0) 0xFFCCCCCC.toInt() else 0xFF777777.toInt() }
    val photo = IntArray(64) { (0xFF shl 24) or (it * 4 shl 16) or ((63 - it) * 4 shl 8) or (it * 2) }
    check(PhotoRules.isFlat(grey), "one colour is flat")
    check(PhotoRules.isFlat(silhouette), "a two-tone silhouette is flat")
    check(!PhotoRules.isFlat(photo), "a real picture isn't")

    check(PhotoRules.looksAlike(photo, photo), "identical samples match")
    check(!PhotoRules.looksAlike(photo, grey), "different samples don't")
    check(!PhotoRules.looksAlike(IntArray(0), IntArray(0)), "empty never matches")

    val rows = listOf(
        PhotoRules.Stored("old-dp", 1, false, 1),
        PhotoRules.Stored("new-dp", 1, false, 9),
        PhotoRules.Stored("oldest-chosen", 2, true, 0),
        PhotoRules.Stored("initials", 0, false, 0),
    )
    check(PhotoRules.evictions(rows, 4).isEmpty(), "under the cap, nothing goes")
    check(PhotoRules.evictions(rows, 3) == listOf("old-dp"), "least recently updated DP goes first")
    check(PhotoRules.evictions(rows, 2) == listOf("old-dp", "new-dp"), "DPs before chosen photos")

    println("PhotoRules OK")
}
