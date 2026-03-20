import 'dart:async';

import 'package:video_pool/src/core/memory/memory_pressure_level.dart';
import 'package:video_pool/src/core/models/thermal_status.dart';
import 'package:video_pool/src/platform/device_capabilities.dart';
import 'package:video_pool/src/platform/device_status.dart';
import 'package:video_pool/src/platform/platform_interface.dart';

/// In-memory mock of [VideoPoolPlatform] for testing.
///
/// Allows tests to control device capabilities and emit arbitrary status
/// updates without native platform channels.
class MockDeviceMonitor implements VideoPoolPlatform {
  /// Capabilities returned by [getCapabilities].
  DeviceCapabilities capabilities;

  /// Whether [requestAudioFocus] will return `true`.
  bool audioFocusGranted;

  /// Controller backing the [statusStream].
  final StreamController<DeviceStatus> statusController =
      StreamController<DeviceStatus>.broadcast();

  /// Controller backing the [audioFocusStream].
  final StreamController<bool> audioFocusController =
      StreamController<bool>.broadcast();

  /// Creates a [MockDeviceMonitor] with sensible defaults.
  MockDeviceMonitor({
    this.capabilities = const DeviceCapabilities(
      maxHardwareDecoders: 4,
      supportedCodecs: ['video/avc', 'video/hevc'],
      totalMemoryBytes: 4 * 1024 * 1024 * 1024, // 4 GB
      maxSupportedResolution: '1920x1080',
    ),
    this.audioFocusGranted = true,
  });

  bool _isMonitoring = false;

  /// Whether monitoring has been started.
  bool get isMonitoring => _isMonitoring;

  @override
  Future<DeviceCapabilities> getCapabilities() async => capabilities;

  @override
  Future<void> startMonitoring() async {
    _isMonitoring = true;
  }

  @override
  Future<void> stopMonitoring() async {
    _isMonitoring = false;
  }

  @override
  Stream<DeviceStatus> get statusStream => statusController.stream;

  @override
  Future<bool> requestAudioFocus() async => audioFocusGranted;

  @override
  Future<void> releaseAudioFocus() async {}

  @override
  Stream<bool> get audioFocusStream => audioFocusController.stream;

  /// Emits an audio focus change event to listeners.
  void emitAudioFocusChange(bool gained) {
    audioFocusController.add(gained);
  }

  /// Emits a status update to listeners.
  void emitStatus(DeviceStatus status) {
    statusController.add(status);
  }

  /// Emits a status update with the given [thermalLevel] and [memoryPressureLevel].
  ///
  /// Convenience method for tests that only care about a subset of fields.
  void emitSimpleStatus({
    ThermalLevel thermalLevel = ThermalLevel.nominal,
    MemoryPressureLevel memoryPressureLevel = MemoryPressureLevel.normal,
    int availableMemoryBytes = 2 * 1024 * 1024 * 1024, // 2 GB
    double batteryLevel = 1.0,
    bool isLowPowerMode = false,
  }) {
    emitStatus(DeviceStatus(
      thermalLevel: thermalLevel,
      availableMemoryBytes: availableMemoryBytes,
      memoryPressureLevel: memoryPressureLevel,
      batteryLevel: batteryLevel,
      isLowPowerMode: isLowPowerMode,
    ));
  }

  /// Disposes the controllers.
  void dispose() {
    statusController.close();
    audioFocusController.close();
  }
}
