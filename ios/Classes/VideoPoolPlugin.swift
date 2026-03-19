import Flutter
import UIKit
import AVFoundation

public class VideoPoolPlugin: NSObject, FlutterPlugin {
    private var deviceMonitor: DeviceMonitor?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let methodChannel = FlutterMethodChannel(
            name: "dev.video_pool/device_monitor",
            binaryMessenger: registrar.messenger()
        )
        let eventChannel = FlutterEventChannel(
            name: "dev.video_pool/device_status",
            binaryMessenger: registrar.messenger()
        )

        let instance = VideoPoolPlugin()
        instance.deviceMonitor = DeviceMonitor()

        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        eventChannel.setStreamHandler(instance.deviceMonitor)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getCapabilities":
            result(HardwareCapabilities.getCapabilities())

        case "startMonitoring":
            deviceMonitor?.startMonitoring()
            result(nil)

        case "stopMonitoring":
            deviceMonitor?.stopMonitoring()
            result(nil)

        case "requestAudioFocus":
            let granted = requestAudioFocus()
            result(granted)

        case "releaseAudioFocus":
            releaseAudioFocus()
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Audio Focus

    private func requestAudioFocus() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
            return true
        } catch {
            return false
        }
    }

    private func releaseAudioFocus() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Best-effort deactivation; nothing to do on failure.
        }
    }
}
