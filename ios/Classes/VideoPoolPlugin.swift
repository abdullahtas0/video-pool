import Flutter
import UIKit
import AVFoundation

public class VideoPoolPlugin: NSObject, FlutterPlugin {
    private var deviceMonitor: DeviceMonitor?
    private var methodChannel: FlutterMethodChannel?
    private var interruptionObserver: NSObjectProtocol?

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
        instance.methodChannel = methodChannel
        instance.setupInterruptionObserver()

        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        eventChannel.setStreamHandler(instance.deviceMonitor)
    }

    private func setupInterruptionObserver() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                return
            }
            switch type {
            case .began:
                self?.methodChannel?.invokeMethod("onAudioFocusChange", arguments: ["status": "lost"])
            case .ended:
                // Only resume if the system indicates it is appropriate.
                let options = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                if AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                    self?.methodChannel?.invokeMethod("onAudioFocusChange", arguments: ["status": "gained"])
                }
            @unknown default:
                break
            }
        }
    }

    deinit {
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
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
