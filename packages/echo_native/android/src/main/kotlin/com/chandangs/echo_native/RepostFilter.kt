package com.chandangs.echo_native

/**
 * Tells a notification apps post again unchanged (a progress tick, a
 * re-alert, a refresh of the same email) from a new one, so Echo captures
 * each once. A notification is the same one when it has the same key as
 * Android gives it (`StatusBarNotification.key`) and the same content; a
 * changed text under the same key is news and passes. Once the owner or the
 * app removes it, it's [forget]ten, so the same text posted again later
 * (tomorrow's reminder) is captured again.
 *
 * Remembers the [capacity] most recent keys. Plain JVM, so it's unit-tested
 * as is; not thread-safe (the listener calls it on its main thread).
 */
class RepostFilter(private val capacity: Int = 500) {
    private val contentByKey = object : LinkedHashMap<String, Int>(64, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Int>?) = size > capacity
    }

    /**
     * True when [key] was last seen with this [content]; otherwise
     * remembers it and returns false.
     */
    fun isRepost(key: String, content: String): Boolean {
        val hash = content.hashCode()
        if (contentByKey[key] == hash) return true
        contentByKey[key] = hash
        return false
    }

    /** Forgets [key], once its notification is gone. */
    fun forget(key: String) {
        contentByKey.remove(key)
    }
}
