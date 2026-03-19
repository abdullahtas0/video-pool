import 'package:flutter/foundation.dart';

import '../core/memory/memory_pressure_level.dart';
import '../core/models/thermal_status.dart';

/// A snapshot of current device health reported by the native platform.
///
/// Delivered periodically via the status stream and used by the pool
/// manager to adjust concurrency, pause preloading, or trigger emergency
/// disposal of player instances.
@immutable
class DeviceStatus {
  /// Creates a new [DeviceStatus].
  ///
  /// - [batteryLevel] must be between 0.0 and 1.0 (inclusive).
  const DeviceStatus({
    required this.thermalLevel,
    required this.availableMemoryBytes,
    required this.memoryPressureLevel,
    required this.batteryLevel,
    required this.isLowPowerMode,
  }) : assert(
          batteryLevel >= 0.0 && batteryLevel <= 1.0,
          'batteryLevel must be 0.0–1.0',
        );

  /// Creates a [DeviceStatus] from a platform channel map.
  factory DeviceStatus.fromMap(Map<String, dynamic> map) {
    return DeviceStatus(
      thermalLevel: ThermalLevel.values[map['thermalLevel'] as int? ?? 0],
      availableMemoryBytes: map['availableMemoryBytes'] as int? ?? 0,
      memoryPressureLevel: MemoryPressureLevel
          .values[map['memoryPressureLevel'] as int? ?? 0],
      batteryLevel: (map['batteryLevel'] as num?)?.toDouble() ?? 1.0,
      isLowPowerMode: map['isLowPowerMode'] as bool? ?? false,
    );
  }

  /// Current thermal level of the device.
  final ThermalLevel thermalLevel;

  /// Available (free) memory in bytes.
  final int availableMemoryBytes;

  /// Categorized memory pressure level.
  final MemoryPressureLevel memoryPressureLevel;

  /// Battery level from 0.0 (empty) to 1.0 (full).
  final double batteryLevel;

  /// Whether the device is in low-power / battery-saver mode.
  final bool isLowPowerMode;

  /// Converts this to a platform channel map.
  Map<String, dynamic> toMap() {
    return {
      'thermalLevel': thermalLevel.index,
      'availableMemoryBytes': availableMemoryBytes,
      'memoryPressureLevel': memoryPressureLevel.index,
      'batteryLevel': batteryLevel,
      'isLowPowerMode': isLowPowerMode,
    };
  }

  /// Creates a copy of this [DeviceStatus] with the given fields replaced.
  DeviceStatus copyWith({
    ThermalLevel? thermalLevel,
    int? availableMemoryBytes,
    MemoryPressureLevel? memoryPressureLevel,
    double? batteryLevel,
    bool? isLowPowerMode,
  }) {
    return DeviceStatus(
      thermalLevel: thermalLevel ?? this.thermalLevel,
      availableMemoryBytes: availableMemoryBytes ?? this.availableMemoryBytes,
      memoryPressureLevel: memoryPressureLevel ?? this.memoryPressureLevel,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      isLowPowerMode: isLowPowerMode ?? this.isLowPowerMode,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DeviceStatus &&
        other.thermalLevel == thermalLevel &&
        other.availableMemoryBytes == availableMemoryBytes &&
        other.memoryPressureLevel == memoryPressureLevel &&
        other.batteryLevel == batteryLevel &&
        other.isLowPowerMode == isLowPowerMode;
  }

  @override
  int get hashCode => Object.hash(
        thermalLevel,
        availableMemoryBytes,
        memoryPressureLevel,
        batteryLevel,
        isLowPowerMode,
      );

  @override
  String toString() =>
      'DeviceStatus(thermalLevel: $thermalLevel, '
      'availableMemoryBytes: $availableMemoryBytes, '
      'memoryPressureLevel: $memoryPressureLevel, '
      'batteryLevel: $batteryLevel, '
      'isLowPowerMode: $isLowPowerMode)';
}
