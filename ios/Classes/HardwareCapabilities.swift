import Foundation
import AVFoundation
import VideoToolbox

/// Queries device hardware capabilities for video decoding.
class HardwareCapabilities {

    /// Returns a dictionary of device capabilities suitable for sending
    /// over a Flutter platform channel.
    static func getCapabilities() -> [String: Any] {
        return [
            "maxHardwareDecoders": getMaxHardwareDecoders(),
            "supportedCodecs": getSupportedCodecs(),
            "totalMemoryBytes": Int(ProcessInfo.processInfo.physicalMemory),
            "maxSupportedResolution": getMaxSupportedResolution(),
        ]
    }

    // MARK: - Hardware Decoders

    /// Estimates the number of concurrent hardware decoders available.
    ///
    /// Apple does not expose an exact count; we estimate based on device
    /// memory class. Devices with more RAM generally support more sessions.
    private static func getMaxHardwareDecoders() -> Int {
        let totalGB = Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
        if totalGB >= 6 {
            return 4
        } else if totalGB >= 4 {
            return 3
        } else {
            return 2
        }
    }

    // MARK: - Supported Codecs

    /// Returns a list of hardware-supported video codec identifiers.
    private static func getSupportedCodecs() -> [String] {
        var codecs: [String] = []

        // H.264 / AVC
        if VTIsHardwareDecodeSupported(kCMVideoCodecType_H264) {
            codecs.append("video/avc")
        }

        // H.265 / HEVC
        if VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC) {
            codecs.append("video/hevc")
        }

        // VP9 (available on Apple Silicon devices)
        if #available(iOS 14.0, *) {
            if VTIsHardwareDecodeSupported(kCMVideoCodecType_VP9) {
                codecs.append("video/x-vnd.on2.vp9")
            }
        }

        return codecs
    }

    // MARK: - Resolution

    /// Returns the maximum resolution the device can reliably decode.
    private static func getMaxSupportedResolution() -> String {
        let totalGB = Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
        if totalGB >= 6 {
            return "3840x2160" // 4K
        } else if totalGB >= 4 {
            return "2560x1440" // 1440p
        } else {
            return "1920x1080" // 1080p
        }
    }
}
