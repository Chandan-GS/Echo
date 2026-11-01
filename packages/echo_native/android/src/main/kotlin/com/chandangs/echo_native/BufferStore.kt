package com.chandangs.echo_native

import java.io.File
import java.io.FileOutputStream
import java.util.UUID

/**
 * The notifications [NotificationBuffer] keeps until Dart has saved them, as
 * an append-only file: one line per notification, `key<TAB>capturedAtMs<TAB>json`.
 * Appending writes one line, whatever the backlog, and nothing is lost to a
 * kill mid-ingest: [peek] only lends a batch out, and it's deleted once Dart
 * [ack]s it. A batch lent out isn't lent again until its lease runs out
 * (or the process dies), so two isolates draining at once get different
 * batches.
 *
 * Plain JVM (no Android or org.json), so it's unit-tested as is. Not
 * thread-safe: [NotificationBuffer] holds the lock.
 */
class BufferStore(
    private val file: File,
    private val maxEntries: Int = MAX_ENTRIES,
    private val maxAgeMs: Long = MAX_AGE_MS,
    private val leaseMs: Long = LEASE_MS,
) {
    class Entry(val key: String, val capturedAt: Long, val json: String)

    /** Lines in the file, counted on first use. */
    private var count = -1

    /** Keys lent out by [peek] → when the lease runs out. */
    private val leases = HashMap<String, Long>()

    val size: Int
        get() = open()

    fun append(json: String, now: Long, key: String = UUID.randomUUID().toString()) {
        appendAll(listOf(Entry(key, now, json)), now)
    }

    fun appendAll(entries: List<Entry>, now: Long) {
        if (entries.isEmpty()) return
        open()
        FileOutputStream(file, true).use { out ->
            out.write(entries.joinToString("") { line(it) }.toByteArray())
            out.fd.sync()
        }
        count += entries.size
        // Trimmed now and then rather than on every append, so appending
        // stays one write.
        if (count > maxEntries + maxEntries / 10) compact(now)
    }

    /**
     * Lends out up to [limit] of the oldest notifications not already lent,
     * dropping what's past the caps first.
     */
    fun peek(limit: Int, now: Long): List<Entry> {
        open()
        leases.entries.removeAll { it.value <= now }
        if (count > maxEntries || (oldest()?.capturedAt ?: now) < now - maxAgeMs) compact(now)
        val out = ArrayList<Entry>()
        val taken = HashSet<String>()
        if (count == 0) return out
        file.bufferedReader().useLines { lines ->
            for (raw in lines) {
                val e = parse(raw) ?: continue
                if (e.key in leases || !taken.add(e.key)) continue
                out.add(e)
                if (out.size >= limit) break
            }
        }
        for (e in out) leases[e.key] = now + leaseMs
        return out
    }

    /** Deletes what Dart has saved. Anything appended meanwhile stays. */
    fun ack(keys: Collection<String>) {
        if (keys.isEmpty()) return
        val done = keys.toHashSet()
        leases.keys.removeAll(done)
        open()
        rewrite { it.key !in done }
    }

    /** Opens the file, mending a line cut short by a kill mid-append. */
    private fun open(): Int {
        if (count >= 0) return count
        file.parentFile?.mkdirs()
        if (!file.exists()) file.createNewFile()
        val bytes = file.length()
        if (bytes > 0) {
            val tail = file.inputStream().use { it.skip(bytes - 1); it.read() }
            if (tail != '\n'.code) {
                // The torn line would swallow the next one appended.
                rewrite { true }
                return count
            }
        }
        count = file.bufferedReader().useLines { lines -> lines.count() }
        return count
    }

    private fun oldest(): Entry? =
        file.bufferedReader().useLines { lines -> lines.firstNotNullOfOrNull { parse(it) } }

    /** Drops what's older than [maxAgeMs], then all but the newest [maxEntries]. */
    private fun compact(now: Long) {
        val cutoff = now - maxAgeMs
        val fresh = file.bufferedReader().useLines { lines ->
            lines.mapNotNull { parse(it) }.filter { it.capturedAt >= cutoff }.count()
        }
        var skip = fresh - maxEntries
        rewrite { e ->
            when {
                e.capturedAt < cutoff -> false
                skip > 0 -> { skip--; false }
                else -> true
            }
        }
    }

    /** Rewrites the file with the entries [keep] accepts, atomically. */
    private fun rewrite(keep: (Entry) -> Boolean) {
        val tmp = File(file.path + ".tmp")
        var kept = 0
        FileOutputStream(tmp).use { out ->
            val writer = out.bufferedWriter()
            if (file.exists()) {
                file.bufferedReader().useLines { lines ->
                    for (raw in lines) {
                        val e = parse(raw) ?: continue
                        if (!keep(e)) continue
                        writer.write(line(e))
                        kept++
                    }
                }
            }
            writer.flush()
            out.fd.sync()
        }
        if (!tmp.renameTo(file)) {
            tmp.delete()
            throw java.io.IOException("Couldn't replace ${file.name}")
        }
        count = kept
    }

    private fun line(e: Entry) = "${e.key}\t${e.capturedAt}\t${e.json}\n"

    private fun parse(raw: String): Entry? {
        val a = raw.indexOf('\t')
        val b = if (a < 0) -1 else raw.indexOf('\t', a + 1)
        if (a <= 0 || b < 0) return null
        val at = raw.substring(a + 1, b).toLongOrNull() ?: return null
        val json = raw.substring(b + 1)
        if (!json.startsWith("{") || !json.endsWith("}")) return null
        return Entry(raw.substring(0, a), at, json)
    }

    companion object {
        /**
         * The newest notifications kept. At the 250 a day the catch-up
         * benchmark assumes that's 20 days; at a heavy 700 a day, a week.
         * Lines run 300–500 bytes, so the file stays around 2 MB. Anything
         * older is over a day old by then, so mostly what the Vault would
         * delete on arrival anyway.
         */
        const val MAX_ENTRIES = 5000

        /** IsarDataSource._maxRetention: nothing older is ever kept. */
        const val MAX_AGE_MS = 180L * 24 * 60 * 60 * 1000

        /**
         * How long a batch lent to Dart stays lent. A batch saves in well
         * under this; if Dart dies holding one, it's lent again after.
         */
        const val LEASE_MS = 5L * 60 * 1000
    }
}
