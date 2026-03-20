import 'package:flutter/foundation.dart';

import 'event_ring_buffer.dart';
import 'pool_event.dart';

/// A point-in-time metrics summary computed lazily from an [EventRingBuffer].
///
/// All fields are computed in a single pass over the buffer's snapshot,
/// making this an O(n) operation where n is the number of stored events.
/// The resulting object is immutable and safe to share across isolates.
@immutable
class MetricsSnapshot {
  /// Creates a metrics snapshot with pre-computed values.
  const MetricsSnapshot({
    required this.computedAt,
    required this.cacheHitRate,
    required this.avgSwapLatencyMs,
    required this.throttleCount,
    required this.totalEvents,
    this.avgBandwidthBytesPerSec = 0.0,
    this.predictionAccuracy = 0.0,
  });

  /// The wall-clock time this snapshot was computed, in milliseconds since epoch.
  final int computedAt;

  /// The cache hit rate as a ratio from 0.0 to 1.0.
  ///
  /// Computed as `hits / (hits + misses)`. Only [CacheAction.hit] and
  /// [CacheAction.miss] events contribute; [CacheAction.evict] and
  /// [CacheAction.prefetchComplete] are excluded.
  /// Returns 0.0 when there are no hits or misses.
  final double cacheHitRate;

  /// The average swap latency in milliseconds across all [SwapEvent]s.
  ///
  /// Returns 0.0 when there are no swap events in the buffer.
  final double avgSwapLatencyMs;

  /// The number of [ThrottleEvent]s recorded in the buffer.
  final int throttleCount;

  /// The total number of events currently stored in the buffer.
  final int totalEvents;

  /// The average bandwidth estimate in bytes/second across all
  /// [BandwidthSampleEvent]s. Returns 0.0 when there are no samples.
  final double avgBandwidthBytesPerSec;

  /// The ratio of resolved predictions where |predicted - actual| <= 1.
  ///
  /// Only [PredictionEvent]s with a non-null [PredictionEvent.actualIndex] are
  /// considered. Returns 0.0 when there are no resolved predictions.
  final double predictionAccuracy;

  /// Computes a [MetricsSnapshot] from the current contents of [buffer].
  ///
  /// Iterates over the buffer's snapshot exactly once, accumulating all
  /// metrics in a single pass using Dart 3 pattern matching.
  factory MetricsSnapshot.fromBuffer(EventRingBuffer buffer) {
    final events = buffer.snapshot();

    var hits = 0;
    var misses = 0;
    var swapCount = 0;
    var swapDurationSum = 0;
    var throttles = 0;
    var bandwidthSampleCount = 0;
    var bandwidthSum = 0;
    var predictionResolvedCount = 0;
    var predictionAccurateCount = 0;

    for (final event in events) {
      switch (event) {
        case CacheEvent(:final action):
          switch (action) {
            case CacheAction.hit:
              hits++;
            case CacheAction.miss:
              misses++;
            case CacheAction.evict:
            case CacheAction.prefetchComplete:
              break;
          }
        case SwapEvent(:final durationMs):
          swapCount++;
          swapDurationSum += durationMs;
        case ThrottleEvent():
          throttles++;
        case BandwidthSampleEvent(:final estimatedBytesPerSec):
          bandwidthSampleCount++;
          bandwidthSum += estimatedBytesPerSec;
        case PredictionEvent(:final predictedIndex, :final actualIndex):
          if (actualIndex != null) {
            predictionResolvedCount++;
            if ((predictedIndex - actualIndex).abs() <= 1) {
              predictionAccurateCount++;
            }
          }
        case _:
          break;
      }
    }

    final hitMissTotal = hits + misses;

    return MetricsSnapshot(
      computedAt: DateTime.now().millisecondsSinceEpoch,
      cacheHitRate: hitMissTotal > 0 ? hits / hitMissTotal : 0.0,
      avgSwapLatencyMs:
          swapCount > 0 ? swapDurationSum / swapCount.toDouble() : 0.0,
      throttleCount: throttles,
      totalEvents: events.length,
      avgBandwidthBytesPerSec: bandwidthSampleCount > 0
          ? bandwidthSum / bandwidthSampleCount.toDouble()
          : 0.0,
      predictionAccuracy: predictionResolvedCount > 0
          ? predictionAccurateCount / predictionResolvedCount.toDouble()
          : 0.0,
    );
  }
}
