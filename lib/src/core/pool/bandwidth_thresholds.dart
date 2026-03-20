import 'package:flutter/foundation.dart';

/// Bandwidth thresholds for network-aware preload adjustment.
///
/// Used by the lifecycle orchestrator to reduce preload count when network
/// conditions are poor, preventing buffering stalls and wasted bandwidth.
@immutable
class BandwidthThresholds {
  /// Creates bandwidth thresholds with sensible defaults.
  const BandwidthThresholds({
    this.highBandwidth = 2 * 1024 * 1024, // 2 MB/s
    this.mediumBandwidth = 500 * 1024, // 500 KB/s
    this.lowBandwidth = 100 * 1024, // 100 KB/s
    this.hysteresisPercent = 10, // 10% buffer zone
  });

  /// Bytes/sec above which full preload is active.
  final int highBandwidth;

  /// Bytes/sec above which reduced preload is active.
  final int mediumBandwidth;

  /// Bytes/sec below which preload is disabled.
  final int lowBandwidth;

  /// Percentage buffer zone to prevent flip-flopping at boundaries
  /// (Schmitt Trigger).
  final int hysteresisPercent;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BandwidthThresholds &&
        other.highBandwidth == highBandwidth &&
        other.mediumBandwidth == mediumBandwidth &&
        other.lowBandwidth == lowBandwidth &&
        other.hysteresisPercent == hysteresisPercent;
  }

  @override
  int get hashCode => Object.hash(
        highBandwidth,
        mediumBandwidth,
        lowBandwidth,
        hysteresisPercent,
      );
}
