package com.videopool

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/// Flutter plugin that bridges native Android device monitoring to Dart.
///
/// Registers a [MethodChannel] for request/response calls and an
/// [EventChannel] for streaming device status updates.
class VideoPoolPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var deviceMonitor: DeviceMonitor? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = MethodChannel(
            binding.binaryMessenger,
            "dev.video_pool/device_monitor"
        )
        eventChannel = EventChannel(
            binding.binaryMessenger,
            "dev.video_pool/device_status"
        )

        deviceMonitor = DeviceMonitor(binding.applicationContext).also {
            it.methodChannel = methodChannel
        }

        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(deviceMonitor)

        // Register thumbnail extraction channel.
        val thumbnailChannel = MethodChannel(
            binding.binaryMessenger,
            "dev.video_pool/thumbnail"
        )
        ThumbnailExtractor.register(thumbnailChannel)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        deviceMonitor?.stopMonitoring()
        deviceMonitor = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getCapabilities" -> {
                val context = deviceMonitor?.context
                if (context != null) {
                    result.success(HardwareCapabilities.getCapabilities(context))
                } else {
                    result.error("NO_CONTEXT", "Application context not available", null)
                }
            }

            "startMonitoring" -> {
                deviceMonitor?.startMonitoring()
                result.success(null)
            }

            "stopMonitoring" -> {
                deviceMonitor?.stopMonitoring()
                result.success(null)
            }

            "requestAudioFocus" -> {
                val granted = deviceMonitor?.requestAudioFocus() ?: false
                result.success(granted)
            }

            "releaseAudioFocus" -> {
                deviceMonitor?.releaseAudioFocus()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }
}
