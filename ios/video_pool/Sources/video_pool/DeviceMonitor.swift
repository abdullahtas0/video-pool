import Flutter
import Foundation
import UIKit

/// Monitors device thermal state, available memory, battery level, and
/// low-power mode. Streams periodic status updates to the Dart side via
/// a Flutter EventChannel.
class DeviceMonitor: NSObject, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    private var thermalObserver: NSObjectProtocol?
    private var lowPowerObserver: NSObjectProtocol?
    private var statusTimer: Timer?

    /// Interval between periodic status updates (seconds).
    private let updateInterval: TimeInterval = 2.0

    // MARK: - FlutterStreamHandler

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        startMonitoring()
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        stopMonitoring()
        eventSink = nil
        return nil
    }

    // MARK: - Monitoring

    func startMonitoring() {
        // Enable battery monitoring
        UIDevice.current.isBatteryMonitoringEnabled = true

        // Observe thermal state changes
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.sendStatusUpdate()
        }

        // Observe low-power mode changes
        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.sendStatusUpdate()
        }

        // Periodic timer for memory and battery updates
        statusTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.sendStatusUpdate()
        }

        // Send initial status immediately
        sendStatusUpdate()
    }

    func stopMonitoring() {
        statusTimer?.invalidate()
        statusTimer = nil

        if let observer = thermalObserver {
            NotificationCenter.default.removeObserver(observer)
            thermalObserver = nil
        }

        if let observer = lowPowerObserver {
            NotificationCenter.default.removeObserver(observer)
            lowPowerObserver = nil
        }

        UIDevice.current.isBatteryMonitoringEnabled = false
    }

    // MARK: - Status

    private func sendStatusUpdate() {
        guard let sink = eventSink else { return }

        let status: [String: Any] = [
            "thermalLevel": mapThermalState(ProcessInfo.processInfo.thermalState),
            "availableMemoryBytes": getAvailableMemory(),
            "memoryPressureLevel": mapMemoryPressure(),
            "batteryLevel": getBatteryLevel(),
            "isLowPowerMode": ProcessInfo.processInfo.isLowPowerModeEnabled,
        ]

        sink(status)
    }

    // MARK: - Thermal Mapping

    /// Maps iOS thermal state to the ThermalLevel enum index on the Dart side.
    /// .nominal → 0, .fair → 1, .serious → 2, .critical → 3
    private func mapThermalState(_ state: ProcessInfo.ThermalState) -> Int {
        switch state {
        case .nominal:
            return 0
        case .fair:
            return 1
        case .serious:
            return 2
        case .critical:
            return 3
        @unknown default:
            return 0
        }
    }

    // MARK: - Memory

    /// Returns available memory in bytes using os_proc_available_memory (iOS 13+).
    private func getAvailableMemory() -> Int {
        return Int(os_proc_available_memory())
    }

    /// Categorizes current memory pressure into MemoryPressureLevel index.
    /// 0 = normal, 1 = warning, 2 = critical, 3 = terminal
    private func mapMemoryPressure() -> Int {
        let available = os_proc_available_memory()
        let total = ProcessInfo.processInfo.physicalMemory

        // Calculate percentage of memory still available
        let ratio = Double(available) / Double(total)

        if ratio > 0.25 {
            return 0 // normal
        } else if ratio > 0.15 {
            return 1 // warning
        } else if ratio > 0.08 {
            return 2 // critical
        } else {
            return 3 // terminal
        }
    }

    // MARK: - Battery

    /// Returns battery level as 0.0–1.0, defaulting to 1.0 when unknown.
    private func getBatteryLevel() -> Double {
        let level = UIDevice.current.batteryLevel
        // batteryLevel is -1.0 when monitoring is disabled or on simulator
        return level >= 0 ? Double(level) : 1.0
    }
}
