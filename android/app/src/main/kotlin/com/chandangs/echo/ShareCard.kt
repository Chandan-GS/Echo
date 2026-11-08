package com.chandangs.echo

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Log

/**
 * The "Share your week" picture: saved into the phone's Pictures/Echo through
 * MediaStore, which needs no storage permission and hands back a content uri
 * other apps can open, then offered through the normal Android share sheet.
 * The picture only ever holds numbers and the mascot (see share_week_sheet.dart).
 */
object ShareCard {
    private const val TAG = "ShareCard"

    private fun save(context: Context, png: ByteArray): Uri? {
        return try {
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, "echo-week-${System.currentTimeMillis()}.png")
                put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/Echo")
                }
            }
            val resolver = context.contentResolver
            val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: return null
            resolver.openOutputStream(uri)?.use { it.write(png) } ?: return null
            uri
        } catch (e: Exception) {
            // Android 9 and older need a storage permission Echo doesn't ask for.
            Log.w(TAG, "Couldn't save the picture", e)
            null
        }
    }

    fun saveToPhotos(context: Context, png: ByteArray?): Boolean =
        png != null && save(context, png) != null

    fun share(context: Context, png: ByteArray?): Boolean {
        val uri = png?.let { save(context, it) } ?: return false
        val send = Intent(Intent.ACTION_SEND)
            .setType("image/png")
            .putExtra(Intent.EXTRA_STREAM, uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        return try {
            context.startActivity(Intent.createChooser(send, null))
            true
        } catch (e: Exception) {
            Log.w(TAG, "Couldn't open the share sheet", e)
            false
        }
    }
}
