package com.chandangs.echo

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import java.io.ByteArrayOutputStream

/** The real launcher icons of other apps, as PNGs for the Vault. */
object AppIcons {

    // Launcher label (normalised) → package, for categories whose package
    // hasn't been seen on a notification yet (e.g. device calendar events).
    @Volatile private var byLabel: Map<String, String>? = null

    /**
     * [packageName]'s icon, or — when it's unknown or uninstalled — the icon
     * of the launcher app whose name matches [label]. Null if neither is found.
     * Adaptive icons come out already masked to the launcher's shape.
     */
    fun png(context: Context, packageName: String?, label: String?, sizePx: Int): ByteArray? {
        val pm = context.packageManager
        val pkg = packageName?.takeIf { isInstalled(pm, it) }
            ?: label?.let { labelIndex(context)[normalise(it)] }
            ?: return null

        val drawable = try {
            pm.getApplicationIcon(pkg)
        } catch (e: PackageManager.NameNotFoundException) {
            return null
        }
        val size = sizePx.coerceIn(24, 512)
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        drawable.setBounds(0, 0, size, size)
        drawable.draw(Canvas(bitmap))
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        bitmap.recycle()
        return out.toByteArray()
    }

    private fun isInstalled(pm: PackageManager, pkg: String): Boolean = try {
        pm.getApplicationInfo(pkg, 0)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }

    private fun labelIndex(context: Context): Map<String, String> {
        byLabel?.let { return it }
        val pm = context.packageManager
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val index = mutableMapOf<String, String>()
        for (info in pm.queryIntentActivities(launcher, 0)) {
            val pkg = info.activityInfo.packageName
            if (pkg == context.packageName) continue
            index.putIfAbsent(normalise(info.loadLabel(pm).toString()), pkg)
        }
        return index.also { byLabel = it }
    }

    private fun normalise(s: String) = s.lowercase().filter { it.isLetterOrDigit() }
}
