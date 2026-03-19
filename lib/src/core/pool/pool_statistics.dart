import 'package:flutter/foundation.dart';

/// Debug metrics for a [VideoPool] instance.
///
/// Provides insight into pool behavior for debugging and performance tuning.
/// Access via [VideoPool.statistics].
@immutable
class PoolStatistics {
  /// Creates a [PoolStatistics] snapshot.
  const PoolStatistics({
    this.totalCreated = 0,
    this.currentActive = 0,
    this.currentIdle = 0,
    this.swapCount = 0,
    this.disposeCount = 0,
    this.cacheHits = 0,
    this.cacheMisses = 0,
    this.estimatedMemoryBytes = 0,
  });

  /// Total number of player instances ever created by this pool.
  final int totalCreated;

  /// Number of player instances currently assigned to a video index.
  final int currentActive;

  /// Number of player instances currently idle (available for reuse).
  final int currentIdle;

  /// Total number of [swapSource] calls performed (instance reuse count).
  final int swapCount;

  /// Total number of [dispose] calls performed (should be low in normal use).
  final int disposeCount;

  /// Number of times a request was served by an already-assigned entry.
  final int cacheHits;

  /// Number of times a new assignment (swapSource) was required.
  final int cacheMisses;

  /// Estimated total memory usage of all pooled players in bytes.
  final int estimatedMemoryBytes;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PoolStatistics &&
        other.totalCreated == totalCreated &&
        other.currentActive == currentActive &&
        other.currentIdle == currentIdle &&
        other.swapCount == swapCount &&
        other.disposeCount == disposeCount &&
        other.cacheHits == cacheHits &&
        other.cacheMisses == cacheMisses &&
        other.estimatedMemoryBytes == estimatedMemoryBytes;
  }

  @override
  int get hashCode => Object.hash(
        totalCreated,
        currentActive,
        currentIdle,
        swapCount,
        disposeCount,
        cacheHits,
        cacheMisses,
        estimatedMemoryBytes,
      );

  @override
  String toString() => 'PoolStatistics('
      'active: $currentActive, '
      'idle: $currentIdle, '
      'swaps: $swapCount, '
      'disposes: $disposeCount, '
      'memory: ${estimatedMemoryBytes ~/ (1024 * 1024)}MB)';
}
