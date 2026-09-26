package com.chandangs.echo

import android.content.Context
import org.json.JSONObject

/**
 * Which apps Echo hears, as chosen in Vault → Apps Echo hears (Dart's
 * AppAccess). Read straight from Flutter's shared prefs so the listener can
 * drop a notification before it's buffered or broadcast.
 */
object AppAccessRules {
    private const val KEY = "flutter.app_access"

    private var cachedRaw: String? = null
    private var hearNewApps = true
    private var on = emptySet<String>()
    private var off = emptySet<String>()

    @Synchronized
    fun hears(context: Context, packageName: String): Boolean {
        val raw = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getString(KEY, null)
        if (raw != cachedRaw) parse(raw)
        return when (packageName) {
            in off -> false
            in on -> true
            else -> hearNewApps
        }
    }

    private fun parse(raw: String?) {
        cachedRaw = raw
        try {
            val json = JSONObject(raw ?: "{}")
            hearNewApps = json.optBoolean("hearNewApps", true)
            on = json.optJSONArray("on").toSet()
            off = json.optJSONArray("off").toSet()
        } catch (e: Exception) {
            hearNewApps = true
            on = emptySet()
            off = emptySet()
        }
    }

    private fun org.json.JSONArray?.toSet(): Set<String> {
        if (this == null) return emptySet()
        return (0 until length()).map { getString(it) }.toSet()
    }
}
