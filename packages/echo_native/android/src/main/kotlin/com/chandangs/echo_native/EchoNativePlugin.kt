package com.chandangs.echo_native

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.concurrent.Executors

/**
 * Native access that must work in EVERY Flutter engine — including the
 * headless one android_alarm_manager_plus spins up for the scheduled briefing.
 * Channels registered in MainActivity only exist while the activity's engine
 * is alive, so the alarm couldn't drain notifications captured overnight.
 * Being a plugin, this is registered automatically in all engines.
 */
class EchoNativePlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "echo_native")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "peekBuffer" -> {
                val limit = call.argument<Number>("limit")?.toInt() ?: 500
                offMain(result) { NotificationBuffer.peek(context, limit) }
            }
            "ackBuffer" -> {
                val keys = call.argument<List<String>>("keys").orEmpty()
                offMain(result) { NotificationBuffer.ack(context, keys); null }
            }
            "fetchCalendarEvents" -> {
                val startMs = call.argument<Number>("startMs")?.toLong()
                val endMs = call.argument<Number>("endMs")?.toLong()
                if (startMs == null || endMs == null) {
                    result.error("bad_args", "startMs and endMs are required", null)
                } else {
                    result.success(CalendarEvents.query(context, startMs, endMs))
                }
            }
            else -> result.notImplemented()
        }
    }

    /** Runs buffer file work off the UI thread, replying on it. */
    private fun offMain(result: Result, work: () -> Any?) {
        io.execute {
            val outcome = runCatching(work)
            main.post {
                outcome.fold(
                    { result.success(it) },
                    { result.error("buffer", it.message, null) },
                )
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    private companion object {
        // Shared by every engine; the buffer's own lock orders the calls.
        val io = Executors.newSingleThreadExecutor()
        val main = Handler(Looper.getMainLooper())
    }
}
