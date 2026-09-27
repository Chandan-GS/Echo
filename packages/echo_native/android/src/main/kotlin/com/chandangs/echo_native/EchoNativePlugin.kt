package com.chandangs.echo_native

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

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
            "drainBuffer" -> result.success(NotificationBuffer.drain(context))
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

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
