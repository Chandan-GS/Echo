package com.chandangs.echo

import com.chandangs.echo.ReminderRules.DAY_MS
import com.chandangs.echo.ReminderRules.RESTORE_DELAY_MS
import com.chandangs.echo.ReminderRules.Stored
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReminderRulesTest {
    private val now = 1_800_000_000_000L
    private val minute = 60_000L

    private fun plan(vararg stored: Stored, fired: Map<String, Long> = emptyMap(), afterBoot: Boolean = true) =
        ReminderRules.plan(stored.toList(), fired, now, afterBoot)

    @Test
    fun `a reminder still to come is set for its own time`() {
        val p = plan(Stored("a", now + 30 * minute, true))
        assertEquals(listOf("a" to now + 30 * minute), p.set)
        assertTrue(p.markFired.isEmpty())
    }

    @Test
    fun `one that came due while the phone was off comes once, shortly after boot`() {
        val p = plan(Stored("a", now - 3 * 60 * minute, true))
        assertEquals(listOf("a" to now + RESTORE_DELAY_MS), p.set)
    }

    @Test
    fun `one that already went off is not sent again`() {
        val at = now - 2 * 60 * minute
        val p = plan(Stored("a", at, true), fired = mapOf("a" to at + 5 * minute))
        assertTrue(p.set.isEmpty())
        // And a second restart changes nothing.
        assertTrue(plan(Stored("a", at, true), fired = mapOf("a" to at + 5 * minute)).set.isEmpty())
    }

    @Test
    fun `a snoozed reminder is unfired again`() {
        val firedAt = now - 5 * minute
        val p = plan(Stored("a", now + 5 * minute, true), fired = mapOf("a" to firedAt))
        assertEquals(listOf("a" to now + 5 * minute), p.set)
    }

    @Test
    fun `a day late is no reminder`() {
        assertTrue(plan(Stored("a", now - DAY_MS - minute, true)).set.isEmpty())
    }

    @Test
    fun `entries without text are skipped`() {
        assertTrue(plan(Stored("a", now + minute, false)).set.isEmpty())
    }

    @Test
    fun `an update re-sets what's to come and marks what's past as fired`() {
        val p = plan(
            Stored("future", now + 10 * minute, true),
            Stored("past", now - 10 * minute, true),
            Stored("done", now - 20 * minute, true),
            fired = mapOf("done" to now - 19 * minute),
            afterBoot = false,
        )
        assertEquals(listOf("future" to now + 10 * minute), p.set)
        assertEquals(listOf("past"), p.markFired)
    }

    @Test
    fun `fired compares against the reminder's current time`() {
        assertFalse(ReminderRules.fired(now, null))
        assertTrue(ReminderRules.fired(now, now))
        assertFalse(ReminderRules.fired(now, now - 1))
    }

    @Test
    fun `prune forgets reminders that fired long ago`() {
        val kept = ReminderRules.prune(mapOf("old" to now - 3 * DAY_MS, "recent" to now - minute), now)
        assertEquals(mapOf("recent" to now - minute), kept)
    }
}
