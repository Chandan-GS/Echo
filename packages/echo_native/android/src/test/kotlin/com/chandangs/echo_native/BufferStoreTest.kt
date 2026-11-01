package com.chandangs.echo_native

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class BufferStoreTest {
    @get:Rule
    val dir = TemporaryFolder()

    private val day = 24L * 60 * 60 * 1000
    private val t0 = 1_800_000_000_000L

    private fun file() = File(dir.root, "buffer.jsonl")

    private fun store(maxEntries: Int = 100, maxAgeMs: Long = 180 * day, leaseMs: Long = 60_000) =
        BufferStore(file(), maxEntries, maxAgeMs, leaseMs)

    private fun json(i: Int) = """{"content":"message $i","timestamp":${t0 + i}}"""

    @Test
    fun `peek lends the oldest first and ack deletes only what was saved`() {
        val s = store()
        for (i in 0 until 10) s.append(json(i), t0 + i, key = "k$i")

        val batch = s.peek(4, t0 + 100)
        assertEquals(listOf("k0", "k1", "k2", "k3"), batch.map { it.key })
        assertEquals(json(0), batch[0].json)

        s.ack(batch.map { it.key })
        assertEquals(6, s.size)
        assertEquals("k4", s.peek(1, t0 + 100).single().key)
    }

    @Test
    fun `a batch not acked is lent again after a restart`() {
        val s = store()
        for (i in 0 until 3) s.append(json(i), t0, key = "k$i")
        assertEquals(3, s.peek(10, t0).size)
        // The app died mid-ingest: nothing acked, and a new process starts.
        val again = store().peek(10, t0 + 1)
        assertEquals(listOf("k0", "k1", "k2"), again.map { it.key })
    }

    @Test
    fun `a batch lent out isn't lent to a second drainer until its lease ends`() {
        val s = store(leaseMs = 60_000)
        for (i in 0 until 6) s.append(json(i), t0, key = "k$i")
        val app = s.peek(3, t0)
        val alarm = s.peek(3, t0 + 1)
        assertEquals(listOf("k0", "k1", "k2"), app.map { it.key })
        assertEquals(listOf("k3", "k4", "k5"), alarm.map { it.key })
        assertTrue(s.peek(10, t0 + 2).isEmpty())
        // The app never confirmed; once its lease runs out, its batch comes back.
        s.ack(alarm.map { it.key })
        assertEquals(listOf("k0", "k1", "k2"), s.peek(10, t0 + 60_001).map { it.key })
    }

    @Test
    fun `a notification arriving mid-drain survives the ack`() {
        val s = store()
        for (i in 0 until 3) s.append(json(i), t0, key = "k$i")
        val batch = s.peek(10, t0)
        s.append(json(99), t0 + 5, key = "late")
        s.ack(batch.map { it.key })
        assertEquals(listOf("late"), s.peek(10, t0 + 6).map { it.key })
    }

    @Test
    fun `keeps only the newest entries, trimming in steps`() {
        val s = store(maxEntries = 100)
        for (i in 0 until 110) s.append(json(i), t0 + i, key = "k$i")
        // Within the 10% slack, appending doesn't trim yet…
        assertEquals(110, s.size)
        s.append(json(110), t0 + 110, key = "k110")
        // …past it, the oldest go.
        assertEquals(100, s.size)
        assertEquals("k11", s.peek(1, t0 + 200).single().key)
    }

    @Test
    fun `peek enforces the cap before lending`() {
        val s = store(maxEntries = 100)
        for (i in 0 until 105) s.append(json(i), t0 + i, key = "k$i")
        assertEquals("k5", s.peek(1, t0 + 200).first().key)
        assertEquals(100, s.size)
    }

    @Test
    fun `drops what's older than the app keeps anything`() {
        val s = store(maxAgeMs = 10 * day)
        s.append(json(0), t0, key = "old")
        s.append(json(1), t0 + 5 * day, key = "newer")
        assertEquals(listOf("old", "newer"), s.peek(10, t0 + 9 * day).map { it.key })
        val later = store(maxAgeMs = 10 * day)
        assertEquals(listOf("newer"), later.peek(10, t0 + 11 * day).map { it.key })
        assertEquals(1, later.size)
    }

    @Test
    fun `a line cut short by a kill is dropped, not glued to the next`() {
        val s = store()
        s.append(json(0), t0, key = "k0")
        file().appendText("k1\t$t0\t{\"content\":\"cut sho")
        val reopened = store()
        reopened.append(json(2), t0, key = "k2")
        assertEquals(listOf("k0", "k2"), reopened.peek(10, t0).map { it.key })
    }

    @Test
    fun `entries moved twice from the old buffer are lent once`() {
        val s = store()
        val moved = listOf(BufferStore.Entry("legacy-0-1", t0, json(0)))
        s.appendAll(moved, t0)
        s.appendAll(moved, t0)
        assertEquals(listOf("legacy-0-1"), s.peek(10, t0).map { it.key })
        s.ack(listOf("legacy-0-1"))
        assertEquals(0, s.size)
    }

    @Test
    fun `tabs and newlines inside a message don't break a line`() {
        val s = store()
        // JSONObject escapes control characters, so a payload is one line.
        val payload = """{"content":"a\tb\nc"}"""
        s.append(payload, t0, key = "k")
        assertEquals(payload, store().peek(1, t0).single().json)
    }
}
