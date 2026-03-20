import '../lifecycle/lifecycle_state.dart';
import '../memory/memory_pressure_level.dart';
import '../models/thermal_status.dart';

/// Base class for all pool events.
///
/// Every event carries a [timestamp] (milliseconds since epoch) recorded at
/// creation time, enabling replay, ordering, and latency analysis.
sealed class PoolEvent {
  /// Creates a pool event with the current time as its timestamp.
  PoolEvent() : timestamp = DateTime.now().millisecondsSinceEpoch;

  /// The wall-clock time this event was created, in milliseconds since epoch.
  final int timestamp;
}

/// Emitted when a player instance swaps its media source to a new index.
///
/// Tracks whether the swap was a warm start (reusing a previously prepared
/// decoder) and how long the swap operation took.
class SwapEvent extends PoolEvent {
  /// Creates a swap event.
  SwapEvent({
    required this.entryId,
    required this.fromIndex,
    required this.toIndex,
    required this.durationMs,
    required this.isWarmStart,
  });

  /// The pool entry (player slot) that performed the swap.
  final int entryId;

  /// The feed index the player was previously assigned to.
  final int fromIndex;

  /// The feed index the player is now assigned to.
  final int toIndex;

  /// How long the swap operation took in milliseconds.
  final int durationMs;

  /// Whether the swap reused a warm decoder pipeline (`true`) or required a
  /// cold start (`false`).
  final bool isWarmStart;
}

/// Emitted after the orchestrator completes a reconciliation pass.
///
/// Contains the counts from the resulting [ReconciliationPlan] so callers
/// can track how the pool is being managed over time.
class ReconcileEvent extends PoolEvent {
  /// Creates a reconcile event.
  ReconcileEvent({
    required this.primaryIndex,
    required this.playCount,
    required this.preloadCount,
    required this.pauseCount,
    required this.releaseCount,
  });

  /// The feed index currently considered primary (most visible).
  final int primaryIndex;

  /// Number of entries moved to the playing state.
  final int playCount;

  /// Number of entries moved to the preloading state.
  final int preloadCount;

  /// Number of entries paused in this reconciliation.
  final int pauseCount;

  /// Number of entries released (returned to idle) in this reconciliation.
  final int releaseCount;
}

/// Emitted when thermal or memory conditions cause the pool to throttle.
///
/// Records the device state and the effective concurrency limit that resulted.
class ThrottleEvent extends PoolEvent {
  /// Creates a throttle event.
  ThrottleEvent({
    required this.thermalLevel,
    required this.memoryPressure,
    required this.effectiveMaxConcurrent,
  });

  /// The current thermal level reported by the OS.
  final ThermalLevel thermalLevel;

  /// The current memory pressure level reported by the OS.
  final MemoryPressureLevel memoryPressure;

  /// The effective maximum concurrent players after throttling is applied.
  final int effectiveMaxConcurrent;
}

/// Actions that can occur on a cache entry.
enum CacheAction {
  /// The requested video was found in the disk cache.
  hit,

  /// The requested video was not in the disk cache.
  miss,

  /// A cached entry was evicted (LRU or size-based).
  evict,

  /// A prefetch download completed and was written to cache.
  prefetchComplete,
}

/// Emitted on disk cache interactions (hit, miss, evict, prefetch complete).
class CacheEvent extends PoolEvent {
  /// Creates a cache event.
  CacheEvent({
    required this.cacheKey,
    required this.action,
    required this.sizeBytes,
    this.downloadDurationMs,
  });

  /// The cache key (typically the video URL or a hash of it).
  final String cacheKey;

  /// What happened to this cache entry.
  final CacheAction action;

  /// The size of the cached data in bytes.
  final int sizeBytes;

  /// How long the download took in milliseconds.
  ///
  /// Only set for [CacheAction.prefetchComplete]; `null` otherwise.
  final int? downloadDurationMs;
}

/// Emitted when a pool entry transitions between lifecycle states.
class LifecycleEvent extends PoolEvent {
  /// Creates a lifecycle event.
  LifecycleEvent({
    required this.entryId,
    required this.index,
    required this.fromState,
    required this.toState,
  });

  /// The pool entry whose state changed.
  final int entryId;

  /// The feed index associated with this entry.
  final int index;

  /// The lifecycle state before the transition.
  final LifecycleState fromState;

  /// The lifecycle state after the transition.
  final LifecycleState toState;
}

/// Emitted when an emergency memory flush disposes all non-primary players.
class EmergencyFlushEvent extends PoolEvent {
  /// Creates an emergency flush event.
  EmergencyFlushEvent({
    required this.survivorEntryId,
    required this.disposedCount,
  });

  /// The entry ID of the surviving (primary) player, or `null` if everything
  /// was disposed.
  final int? survivorEntryId;

  /// The number of player instances that were disposed during the flush.
  final int disposedCount;
}

/// Emitted when an error occurs within the pool or one of its subsystems.
class ErrorEvent extends PoolEvent {
  /// Creates an error event.
  ErrorEvent({
    required this.code,
    required this.message,
    required this.fatal,
  });

  /// A short, machine-readable error code (e.g. `SWAP_TIMEOUT`).
  final String code;

  /// A human-readable description of the error.
  final String message;

  /// Whether the error is fatal (requires user intervention or restart).
  final bool fatal;
}
