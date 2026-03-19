package com.videopool

import android.app.ActivityManager
import android.content.ComponentCallbacks2
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.res.Configuration
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import io.flutter.plugin.common.EventChannel

/// Monitors device thermal state, memory pressure, battery level, and
/// low-power mode on Android. Streams periodic updates to Dart via an
/// [EventChannel].
class DeviceMonitor(val context: Context) : EventChannel.StreamHandler, ComponentCallbacks2 {

    private var eventSink: EventChannel.EventSink? = null
    private val handler = Handler(Looper.getMainLooper())
    private var isMonitoring = false
    private var audioFocusRequest: AudioFocusRequest? = null

    /// Interval between periodic status updates (milliseconds).
    private val updateIntervalMs = 2000L

    private val statusRunnable = object : Runnable {
        override fun run() {
            sendStatusUpdate()
            if (isMonitoring) {
                handler.postDelayed(this, updateIntervalMs)
            }
        }
    }

    // Current memory pressure level tracked via ComponentCallbacks2
    private var currentMemoryPressureLevel = 0

    // MARK: - EventChannel.StreamHandler

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        startMonitoring()
    }

    override fun onCancel(arguments: Any?) {
        stopMonitoring()
        eventSink = null
    }

    // MARK: - Monitoring

    fun startMonitoring() {
        if (isMonitoring) return
        isMonitoring = true

        // Register for memory trim callbacks
        context.registerComponentCallbacks(this)

        // Start periodic updates
        handler.post(statusRunnable)
    }

    fun stopMonitoring() {
        if (!isMonitoring) return
        isMonitoring = false

        handler.removeCallbacks(statusRunnable)

        try {
            context.unregisterComponentCallbacks(this)
        } catch (_: Exception) {
            // Already unregistered — safe to ignore.
        }
    }

    // MARK: - ComponentCallbacks2 (Memory Pressure)

    override fun onTrimMemory(level: Int) {
        currentMemoryPressureLevel = when {
            level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL -> 3 // terminal
            level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW -> 2      // critical
            level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_MODERATE -> 1 // warning
            else -> 0                                                       // normal
        }

        // Immediately send update on memory pressure change
        sendStatusUpdate()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        // Not used; required by ComponentCallbacks2.
    }

    override fun onLowMemory() {
        currentMemoryPressureLevel = 3 // terminal
        sendStatusUpdate()
    }

    // MARK: - Status Update

    private fun sendStatusUpdate() {
        val sink = eventSink ?: return

        val status = mapOf<String, Any>(
            "thermalLevel" to getThermalLevel(),
            "availableMemoryBytes" to getAvailableMemory(),
            "memoryPressureLevel" to currentMemoryPressureLevel,
            "batteryLevel" to getBatteryLevel(),
            "isLowPowerMode" to isLowPowerMode(),
        )

        handler.post { sink.success(status) }
    }

    // MARK: - Thermal

    /// Returns thermal level index: 0=nominal, 1=fair, 2=serious, 3=critical.
    /// PowerManager thermal status is available on API 29+.
    private fun getThermalLevel(): Int {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            return when (powerManager?.currentThermalStatus) {
                PowerManager.THERMAL_STATUS_NONE -> 0
                PowerManager.THERMAL_STATUS_LIGHT -> 1
                PowerManager.THERMAL_STATUS_MODERATE -> 1
                PowerManager.THERMAL_STATUS_SEVERE -> 2
                PowerManager.THERMAL_STATUS_CRITICAL -> 3
                PowerManager.THERMAL_STATUS_EMERGENCY -> 3
                PowerManager.THERMAL_STATUS_SHUTDOWN -> 3
                else -> 0
            }
        }
        return 0 // Default to nominal on older APIs
    }

    // MARK: - Memory

    private fun getAvailableMemory(): Long {
        val activityManager =
            context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        val memInfo = ActivityManager.MemoryInfo()
        activityManager?.getMemoryInfo(memInfo)
        return memInfo.availMem
    }

    // MARK: - Battery

    private fun getBatteryLevel(): Double {
        val batteryStatus = context.registerReceiver(
            null,
            IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        )
        val level = batteryStatus?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = batteryStatus?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        return if (level >= 0 && scale > 0) {
            level.toDouble() / scale.toDouble()
        } else {
            1.0
        }
    }

    // MARK: - Low Power Mode

    private fun isLowPowerMode(): Boolean {
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        return powerManager?.isPowerSaveMode ?: false
    }

    // MARK: - Audio Focus

    fun requestAudioFocus(): Boolean {
        val audioManager =
            context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return false

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val attributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                .build()

            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(attributes)
                .setOnAudioFocusChangeListener { /* handle focus change */ }
                .build()

            audioFocusRequest = request
            val result = audioManager.requestAudioFocus(request)
            return result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        } else {
            @Suppress("DEPRECATION")
            val result = audioManager.requestAudioFocus(
                { /* handle focus change */ },
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN
            )
            return result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        }
    }

    fun releaseAudioFocus() {
        val audioManager =
            context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
            audioFocusRequest = null
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(null)
        }
    }
}
