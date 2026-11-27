package com.chandangs.echo

/**
 * When reminders go off again after the phone restarts or Echo is updated.
 * Kept free of Android types so it can be tested on the JVM.
 */
object ReminderRules {
    const val DAY_MS = 24 * 60 * 60 * 1000L

    /** How soon after a restart a reminder that came due meanwhile goes off. */
    const val RESTORE_DELAY_MS = 60_000L

    /** How long a fired reminder is remembered: past this it's too late to restore anyway. */
    private const val FIRED_KEPT_MS = 2 * DAY_MS

    /** A reminder in the Dart side's list, as far as restoring it goes. */
    data class Stored(val key: String, val at: Long, val hasText: Boolean)

    /**
     * What to do with the stored reminders: [set] holds each one to set again
     * and when, and [markFired] the ones to treat as already gone off.
     */
    data class Plan(val set: List<Pair<String, Long>>, val markFired: List<String>)

    /**
     * Whether a reminder due at [at] has gone off, given when it last fired.
     * A snooze or a new time moves [at] past that, so it counts as unfired
     * again.
     */
    fun fired(at: Long, firedAt: Long?): Boolean = firedAt != null && firedAt >= at

    /**
     * Restoring after a restart ([afterBoot]) or an update. Anything still to
     * come is set again. One that came due while the phone was off goes off
     * once, a minute later, unless it's a day old. An update leaves alarms
     * in place and happens with the phone on, so anything already due then
     * had its turn: it's marked fired rather than sent again, which also
     * covers reminders fired by builds that kept no record.
     */
    fun plan(stored: List<Stored>, firedAt: Map<String, Long>, now: Long, afterBoot: Boolean): Plan {
        val set = mutableListOf<Pair<String, Long>>()
        val markFired = mutableListOf<String>()
        for (r in stored) {
            // Older entries lack the text to show.
            if (!r.hasText || fired(r.at, firedAt[r.key])) continue
            when {
                r.at > now -> set += r.key to r.at
                !afterBoot -> markFired += r.key
                r.at >= now - DAY_MS -> set += r.key to now + RESTORE_DELAY_MS
            }
        }
        return Plan(set, markFired)
    }

    /** [firedAt] without the reminders that fired too long ago to matter. */
    fun prune(firedAt: Map<String, Long>, now: Long): Map<String, Long> =
        firedAt.filterValues { it >= now - FIRED_KEPT_MS }
}
