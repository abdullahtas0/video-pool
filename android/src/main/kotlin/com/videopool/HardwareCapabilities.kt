package com.videopool

import android.app.ActivityManager
import android.content.Context
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.os.Build

/// Queries device hardware capabilities for video decoding on Android.
class HardwareCapabilities {
    companion object {
        /// Returns a map of device capabilities for the Flutter platform channel.
        fun getCapabilities(context: Context): Map<String, Any> {
            val codecs = getSupportedHardwareCodecs()
            return mapOf(
                "maxHardwareDecoders" to getMaxHardwareDecoders(context),
                "supportedCodecs" to codecs,
                "totalMemoryBytes" to getTotalMemory(context),
                "maxSupportedResolution" to getMaxSupportedResolution(context),
            )
        }

        /// Estimates the number of concurrent hardware video decoders.
        ///
        /// Uses the device memory class as a heuristic: more memory generally
        /// means the SoC can sustain more simultaneous decode sessions.
        private fun getMaxHardwareDecoders(context: Context): Int {
            val activityManager =
                context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            val memoryClass = activityManager?.memoryClass ?: 128

            return when {
                memoryClass >= 512 -> 6
                memoryClass >= 256 -> 4
                memoryClass >= 128 -> 3
                else -> 2
            }
        }

        /// Returns MIME types of hardware-accelerated video decoders.
        private fun getSupportedHardwareCodecs(): List<String> {
            val codecList = MediaCodecList(MediaCodecList.ALL_CODECS)
            val hardwareCodecs = mutableSetOf<String>()

            for (info in codecList.codecInfos) {
                // Only decoders, not encoders
                if (info.isEncoder) continue

                // Only hardware-accelerated codecs
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    if (!info.isHardwareAccelerated) continue
                } else {
                    // On older APIs, heuristic: hardware codecs don't start with "OMX.google."
                    if (info.name.startsWith("OMX.google.") || info.name.startsWith("c2.android.")) {
                        continue
                    }
                }

                for (type in info.supportedTypes) {
                    if (type.startsWith("video/")) {
                        hardwareCodecs.add(type)
                    }
                }
            }

            return hardwareCodecs.toList()
        }

        /// Returns total device memory in bytes.
        private fun getTotalMemory(context: Context): Long {
            val activityManager =
                context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            val memInfo = ActivityManager.MemoryInfo()
            activityManager?.getMemoryInfo(memInfo)
            return memInfo.totalMem
        }

        /// Returns estimated max supported resolution based on device capability.
        private fun getMaxSupportedResolution(context: Context): String {
            val activityManager =
                context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            val memInfo = ActivityManager.MemoryInfo()
            activityManager?.getMemoryInfo(memInfo)

            val totalGB = memInfo.totalMem.toDouble() / (1024 * 1024 * 1024)
            return when {
                totalGB >= 8 -> "3840x2160"   // 4K
                totalGB >= 4 -> "2560x1440"   // 1440p
                else -> "1920x1080"            // 1080p
            }
        }
    }
}
