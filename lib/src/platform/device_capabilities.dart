import 'package:flutter/foundation.dart';

/// Describes the hardware capabilities of the current device.
///
/// Queried once at startup and used by the pool manager to set initial
/// concurrency limits (e.g. max simultaneous hardware decoders).
@immutable
class DeviceCapabilities {
  /// Creates a new [DeviceCapabilities].
  const DeviceCapabilities({
    required this.maxHardwareDecoders,
    required this.supportedCodecs,
    required this.totalMemoryBytes,
    this.maxSupportedResolution,
  });

  /// Creates a [DeviceCapabilities] from a platform channel map.
  factory DeviceCapabilities.fromMap(Map<String, dynamic> map) {
    return DeviceCapabilities(
      maxHardwareDecoders: map['maxHardwareDecoders'] as int? ?? 0,
      supportedCodecs: List<String>.from(
        map['supportedCodecs'] as List<dynamic>? ?? <dynamic>[],
      ),
      totalMemoryBytes: map['totalMemoryBytes'] as int? ?? 0,
      maxSupportedResolution: map['maxSupportedResolution'] as String?,
    );
  }

  /// Maximum number of simultaneous hardware video decoders.
  final int maxHardwareDecoders;

  /// List of codec MIME types supported by hardware decoders.
  final List<String> supportedCodecs;

  /// Total physical memory in bytes.
  final int totalMemoryBytes;

  /// Highest resolution the device can reliably decode (e.g. "3840x2160").
  final String? maxSupportedResolution;

  /// Converts this to a platform channel map.
  Map<String, dynamic> toMap() {
    return {
      'maxHardwareDecoders': maxHardwareDecoders,
      'supportedCodecs': supportedCodecs,
      'totalMemoryBytes': totalMemoryBytes,
      'maxSupportedResolution': maxSupportedResolution,
    };
  }

  /// Creates a copy of this [DeviceCapabilities] with the given fields replaced.
  DeviceCapabilities copyWith({
    int? maxHardwareDecoders,
    List<String>? supportedCodecs,
    int? totalMemoryBytes,
    String? maxSupportedResolution,
  }) {
    return DeviceCapabilities(
      maxHardwareDecoders: maxHardwareDecoders ?? this.maxHardwareDecoders,
      supportedCodecs: supportedCodecs ?? this.supportedCodecs,
      totalMemoryBytes: totalMemoryBytes ?? this.totalMemoryBytes,
      maxSupportedResolution:
          maxSupportedResolution ?? this.maxSupportedResolution,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DeviceCapabilities &&
        other.maxHardwareDecoders == maxHardwareDecoders &&
        listEquals(other.supportedCodecs, supportedCodecs) &&
        other.totalMemoryBytes == totalMemoryBytes &&
        other.maxSupportedResolution == maxSupportedResolution;
  }

  @override
  int get hashCode => Object.hash(
        maxHardwareDecoders,
        Object.hashAll(supportedCodecs),
        totalMemoryBytes,
        maxSupportedResolution,
      );

  @override
  String toString() =>
      'DeviceCapabilities(maxHardwareDecoders: $maxHardwareDecoders, '
      'supportedCodecs: $supportedCodecs, '
      'totalMemoryBytes: $totalMemoryBytes, '
      'maxSupportedResolution: $maxSupportedResolution)';
}
