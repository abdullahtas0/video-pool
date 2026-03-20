import 'dart:async';

import 'package:flutter/foundation.dart';

import '../adapter/player_adapter.dart';
import '../cache/bandwidth_estimator.dart';
import '../events/event_ring_buffer.dart';
import '../events/metrics_snapshot.dart';
import '../events/pool_event.dart';
import '../cache/file_preload_manager.dart';
import '../lifecycle/lifecycle_orchestrator.dart';
import '../lifecycle/lifecycle_policy.dart';
import '../lifecycle/lifecycle_state.dart';
import '../memory/memory_manager.dart';
import '../memory/memory_pressure_level.dart';
import '../models/thermal_status.dart';
import '../models/video_source.dart';
import '../prediction/predictive_scroll_engine.dart';
import 'pool_config.dart';
import 'pool_entry.dart';
import 'pool_statistics.dart';
import 'video_pool_logger.dart';

/// Callback to resolve a video index to its [VideoSource].
///
/// The pool calls this when it needs to assign a player to a new index
/// during reconciliation (e.g. for preloading adjacent slots).
typedef VideoSourceResolver = VideoSource? Function(int index);

/// The central video pool coordinator.
///
/// Creates a fixed number of [PlayerAdapter] instances at initialization and
/// reuses them via [PlayerAdapter.swapSource] as the user scrolls. Players
/// are **never** disposed during normal scrolling — only during pool shutdown
/// or emergency memory pressure.
///
/// Usage:
/// ```dart
/// final pool = VideoPool(
///   config: const VideoPoolConfig(),
///   adapterFactory: (id) => MediaKitAdapter(id: id),
///   sourceResolver: (index) => videoSources[index],
/// );
/// ```
class VideoPool {
  /// Creates a [VideoPool] with the given [config] and adapter factory.
  ///
  /// [adapterFactory] is called [config.maxConcurrent] times to create
  /// the initial pool of player instances.
  ///
  /// [sourceResolver] maps a video index to its [VideoSource]. Called during
  /// reconciliation to get the source for preloading/playing.
  ///
  /// [filePreloadManager] enables disk caching. When provided, the pool
  /// checks the cache before network requests and prefetches adjacent videos.
  VideoPool({
    required this.config,
    required PlayerAdapter Function(int id) adapterFactory,
    required VideoSourceResolver sourceResolver,
    FilePreloadManager? filePreloadManager,
  })  : _adapterFactory = adapterFactory,
        _sourceResolver = sourceResolver,
        _filePreloadManager = filePreloadManager,
        _logger = VideoPoolLogger(level: config.logLevel),
        _orchestrator = LifecycleOrchestrator(
          policy: config.lifecyclePolicy ?? const DefaultLifecyclePolicy(),
          logger: VideoPoolLogger(level: config.logLevel),
        ),
        _memoryManager = MemoryManager(
          budgetBytes: config.memoryBudgetBytes,
          logger: VideoPoolLogger(level: config.logLevel),
        ) {
    // Create the initial pool of player instances.
    // Runtime clamp as a safety net beyond assert-level validation.
    final effectiveMaxConcurrent = config.maxConcurrent.clamp(1, 10);
    for (var i = 0; i < effectiveMaxConcurrent; i++) {
      final adapter = adapterFactory(i);
      final entry = PoolEntry(id: _nextEntryId++, adapter: adapter);
      _entries.add(entry);
      _memoryManager.track(entry);
      _totalCreated++;
    }

    _logger.info(
      'Pool initialized with ${_entries.length} entries, '
      'budget: ${config.memoryBudgetBytes ~/ (1024 * 1024)}MB',
    );
  }

  /// Pool configuration.
  final VideoPoolConfig config;

  /// Factory for creating new adapters (used for recovery after emergency flush).
  final PlayerAdapter Function(int id) _adapterFactory;

  /// Optional disk cache manager for preloading video data.
  final FilePreloadManager? _filePreloadManager;

  /// Estimates network bandwidth from prefetch download durations.
  final BandwidthEstimator _bandwidthEstimator = BandwidthEstimator();

  /// Next entry ID (monotonically increasing, never reused).
  int _nextEntryId = 0;

  /// Elapsed time since pool creation.
  ///
  /// Used to prevent emergency flush during the initial warmup period.
  /// Some devices (e.g. MIUI on Redmi) report terminal memory pressure
  /// immediately on app start, which would destroy all entries permanently.
  /// Uses [Stopwatch] instead of [DateTime] for monotonic timing that is
  /// immune to system clock changes.
  final Stopwatch _warmupWatch = Stopwatch()..start();

  /// Resolves a video index to its source.
  final VideoSourceResolver _sourceResolver;

  /// The lifecycle orchestrator.
  final LifecycleOrchestrator _orchestrator;

  /// Memory manager for budget tracking and eviction.
  final MemoryManager _memoryManager;

  /// Logger.
  final VideoPoolLogger _logger;

  /// All pool entries (both active and idle).
  final List<PoolEntry> _entries = [];

  /// Whether the pool has been disposed.
  bool _disposed = false;

  /// Ring buffer storing the last 1000 pool events for metrics computation.
  final EventRingBuffer _eventBuffer = EventRingBuffer();

  /// Broadcast stream controller for pool events.
  final StreamController<PoolEvent> _eventController =
      StreamController<PoolEvent>.broadcast(sync: true);

  /// A broadcast stream of all pool events.
  ///
  /// Listeners receive events in real time. For aggregated metrics, use
  /// the [metrics] getter instead.
  Stream<PoolEvent> get eventStream => _eventController.stream;

  /// Computes a point-in-time metrics snapshot from the event ring buffer.
  MetricsSnapshot get metrics => MetricsSnapshot.fromBuffer(_eventBuffer);

  /// Emits a pool event to both the ring buffer and the stream.
  void _emit(PoolEvent event) {
    if (_disposed) return;
    _eventBuffer.add(event);
    _eventController.add(event);
  }

  /// Notifies listeners when reconciliation completes and entries change.
  ///
  /// Widgets like [VideoCard] listen to this to rebuild when a pool entry
  /// is assigned to their index.
  final ValueNotifier<int> reconciliationNotifier = ValueNotifier<int>(0);

  /// Guards against concurrent reconciliation.
  Future<void>? _activeReconciliation;

  /// Monotonically increasing version to implement "latest wins" for rapid scroll.
  int _reconciliationVersion = 0;

  // --- Statistics counters ---
  int _totalCreated = 0;
  int _swapCount = 0;
  int _disposeCount = 0;
  int _cacheHits = 0;
  int _cacheMisses = 0;

  // --- Device state ---
  ThermalLevel _thermalLevel = ThermalLevel.nominal;
  MemoryPressureLevel _memoryPressure = MemoryPressureLevel.normal;

  // --- Last known visibility state (for resume after background) ---
  int _lastPrimaryIndex = -1;
  Map<int, double> _lastVisibilityRatios = const {};

  // --- Threshold state for deduplication ---
  Set<int> _lastPlayableIndices = {};

  // --- Predictive scroll engine ---
  final PredictiveScrollEngine _scrollEngine = const PredictiveScrollEngine();
  int? _lastPredictedIndex;
  int _predictionStableCount = 0;

  /// Called by the visibility tracker when viewport changes.
  ///
  /// [primaryIndex] is the most visible slot index.
  /// [visibilityRatios] maps visible slot indices to their visibility (0.0–1.0).
  ///
  /// Uses threshold state comparison to skip redundant reconciliations.
  /// Only reconciles when the primary index changes or a video crosses the
  /// [VideoPoolConfig.visibilityPlayThreshold] boundary.
  void onVisibilityChanged({
    required int primaryIndex,
    required Map<int, double> visibilityRatios,
  }) {
    if (_disposed) return;

    // Compute which indices are above the play threshold.
    final currentPlayable = <int>{};
    for (final entry in visibilityRatios.entries) {
      if (entry.value >= config.visibilityPlayThreshold) {
        currentPlayable.add(entry.key);
      }
    }

    // Skip reconciliation if nothing meaningful changed.
    if (primaryIndex == _lastPrimaryIndex &&
        setEquals(_lastPlayableIndices, currentPlayable)) {
      return;
    }

    // State changed — update tracking.
    _lastPrimaryIndex = primaryIndex;
    _lastPlayableIndices = currentPlayable;
    // Store reference directly — no Map.of() copy (zero GC pressure).
    _lastVisibilityRatios = visibilityRatios;

    // Resolve any outstanding scroll prediction.
    if (_lastPredictedIndex != null) {
      _emit(PredictionEvent(
        predictedIndex: _lastPredictedIndex!,
        confidence: 0.0, // resolved
        actualIndex: primaryIndex,
      ));
      _lastPredictedIndex = null;
      _predictionStableCount = 0;
    }

    // "Latest wins" — bump version so stale reconciliations bail out early.
    _reconciliationVersion++;
    final version = _reconciliationVersion;

    // Serialize reconciliation: wait for previous run to finish, then
    // only run if no newer call has superseded us.
    _activeReconciliation = (_activeReconciliation ?? Future<void>.value())
        .then((_) {
      if (version == _reconciliationVersion && !_disposed) {
        return _reconcile(primaryIndex, visibilityRatios);
      }
    });
  }

  /// Called by scroll widgets with current scroll metrics for prediction.
  ///
  /// Runs the predictive scroll engine to estimate where the scroll will
  /// land. When confidence is high enough (>= 0.7) and a [FilePreloadManager]
  /// is available, triggers a disk prefetch for the predicted target video.
  ///
  /// Widgets should call this from [ScrollNotification] handlers or custom
  /// scroll listeners.
  void onScrollUpdate({
    required double position,
    required double velocity,
    required double itemExtent,
    required int itemCount,
  }) {
    if (_disposed) return;

    final prediction = _scrollEngine.predict(
      position: position,
      velocity: velocity,
      itemExtent: itemExtent,
      itemCount: itemCount,
    );

    if (prediction == null) {
      _lastPredictedIndex = null;
      _predictionStableCount = 0;
      return;
    }

    // Target stabilization: if prediction only changed by +/-1, don't
    // re-trigger after the first emission.
    if (_lastPredictedIndex != null &&
        (prediction.targetIndex - _lastPredictedIndex!).abs() <= 1 &&
        _predictionStableCount > 0) {
      return;
    }

    _lastPredictedIndex = prediction.targetIndex;
    _predictionStableCount++;

    _emit(PredictionEvent(
      predictedIndex: prediction.targetIndex,
      confidence: prediction.confidence,
    ));

    // Budget allocation based on confidence.
    if (prediction.confidence >= 0.7) {
      // High confidence: trigger prefetch for target (disk cache only, no
      // decoder allocation).
      final source = _sourceResolver(prediction.targetIndex);
      if (source != null && _filePreloadManager != null) {
        _filePreloadManager.prefetch(source);
      }
    }
    // Low confidence: don't do anything extra, normal adjacent preload
    // handles it.
  }

  /// Internal reconciliation — the heart of the pool.
  ///
  /// 1. Compute effective limits from device conditions.
  /// 2. Delegate to the orchestrator/policy for a plan.
  /// 3. Execute: release, preload, play, pause.
  Future<void> _reconcile(
    int primaryIndex,
    Map<int, double> ratios,
  ) async {
    if (_disposed) return;

    // Step 1: Compute effective limits.
    final limits = _orchestrator.computeEffectiveLimits(
      config: config,
      thermalLevel: _thermalLevel,
      memoryPressure: _memoryPressure,
      bandwidthEstimate: _bandwidthEstimator.estimatedBytesPerSec,
    );

    // Step 2: Determine currently active slot indices.
    final currentlyActive = <int>{};
    for (final entry in _entries) {
      if (entry.assignedIndex != null) {
        currentlyActive.add(entry.assignedIndex!);
      }
    }

    // Step 3: Get reconciliation plan from the orchestrator.
    final plan = _orchestrator.reconcile(
      primaryIndex: primaryIndex,
      visibilityRatios: ratios,
      effectiveMaxConcurrent: limits.maxConcurrent,
      effectivePreloadCount: limits.preloadCount,
      currentlyActive: currentlyActive,
    );

    _emit(ReconcileEvent(
      primaryIndex: primaryIndex,
      playCount: plan.toPlay.length,
      preloadCount: plan.toPreload.length,
      pauseCount: plan.toPause.length,
      releaseCount: plan.toRelease.length,
    ));

    // Step 4: Execute the plan.

    // 4a: Release entries that are no longer needed.
    for (final index in plan.toRelease) {
      final entry = _getEntryForIndex(index);
      if (entry != null) {
        await _releaseEntry(entry);
      }
    }

    // 4b: Preload adjacent slots.
    for (final index in plan.toPreload) {
      final existingEntry = _getEntryForIndex(index);
      if (existingEntry != null) {
        // Already assigned — cache hit.
        _cacheHits++;
        // Safety: if this entry was previously playing but is now only
        // preloaded (not primary), pause it to prevent audio overlap.
        if (existingEntry.lifecycleState == LifecycleState.playing) {
          _logger.debug(
            'Pausing preloaded entry ${existingEntry.id} (was playing)',
          );
          try {
            await existingEntry.adapter.setVolume(0);
            await existingEntry.adapter.pause();
          } catch (e, st) {
            _logger.error(
              'Pause preloaded entry failed for ${existingEntry.id}', e, st,
            );
          }
          existingEntry.lifecycleNotifier.value = LifecycleState.paused;
        }
        continue;
      }
      final source = _sourceResolver(index);
      if (source == null) continue;

      final idleEntry = _findIdleEntry();
      if (idleEntry == null) {
        _logger.warning('No idle entry available for preload of index $index');
        continue;
      }
      _cacheMisses++;
      await _assignEntry(idleEntry, index, source);
      idleEntry.lifecycleNotifier.value = LifecycleState.preparing;
      try {
        await idleEntry.adapter.prepare();
        if (idleEntry.assignedIndex == index) {
          idleEntry.lifecycleNotifier.value = LifecycleState.ready;
        }
      } catch (e, st) {
        _logger.error('Preload failed for index $index', e, st);
        if (idleEntry.assignedIndex == index) {
          idleEntry.lifecycleNotifier.value = LifecycleState.error;
        }
      }
    }

    // 4c: Play the primary index.
    for (final index in plan.toPlay) {
      var entry = _getEntryForIndex(index);
      if (entry != null) {
        _cacheHits++;
      } else {
        final source = _sourceResolver(index);
        if (source == null) continue;
        entry = _findIdleEntry();
        if (entry == null) {
          _logger.warning('No idle entry available for play of index $index');
          continue;
        }
        _cacheMisses++;
        await _assignEntry(entry, index, source);
        entry.lifecycleNotifier.value = LifecycleState.preparing;
        try {
          await entry.adapter.prepare();
        } catch (e, st) {
          _logger.error('Prepare failed for index $index', e, st);
          entry.lifecycleNotifier.value = LifecycleState.error;
          continue;
        }
      }
      entry.lifecycleNotifier.value = LifecycleState.playing;
      try {
        await entry.adapter.play();
      } catch (e, st) {
        _logger.error('Play failed for index $index', e, st);
        entry.lifecycleNotifier.value = LifecycleState.error;
      }
    }

    // 4d: Pause visible-but-not-primary slots.
    for (final index in plan.toPause) {
      final entry = _getEntryForIndex(index);
      if (entry == null) continue;
      entry.lifecycleNotifier.value = LifecycleState.paused;
      try {
        await entry.adapter.pause();
      } catch (e, st) {
        _logger.error('Pause failed for index $index', e, st);
      }
    }

    // Notify widgets that reconciliation is complete so they can rebuild
    // and pick up newly assigned entries.
    reconciliationNotifier.value++;
  }

  /// Release a player from its current assignment back to the idle pool.
  ///
  /// The adapter is NOT disposed — it remains available for reuse.
  Future<void> _releaseEntry(PoolEntry entry) async {
    _logger.debug('Releasing entry ${entry.id} from index ${entry.assignedIndex}');

    // Unlock cache key before releasing.
    if (_filePreloadManager != null && entry.currentSource != null) {
      _filePreloadManager.unlockKey(entry.currentSource!.cacheKey);
    }

    try {
      // Set volume to 0 first to prevent audio bleed during async pause.
      await entry.adapter.setVolume(0);
      await entry.adapter.pause();
    } catch (e, st) {
      _logger.error('Pause during release failed for entry ${entry.id}', e, st);
    }
    entry.release();
  }

  /// Assign an idle entry to a new video index via [swapSource].
  ///
  /// If a [FilePreloadManager] is configured, checks the disk cache first
  /// and uses the local file path instead of the network URL.
  Future<void> _assignEntry(
    PoolEntry entry,
    int index,
    VideoSource source,
  ) async {
    _logger.debug('Assigning entry ${entry.id} to index $index');

    // Check disk cache for a local copy.
    var effectiveSource = source;
    if (_filePreloadManager != null) {
      final cachedPath = _filePreloadManager.getCachedPath(source.cacheKey);
      if (cachedPath != null) {
        effectiveSource = source.copyWith(
          url: cachedPath,
          type: VideoSourceType.file,
        );
        _filePreloadManager.lockKey(source.cacheKey);
        _logger.debug('Cache hit for index $index: $cachedPath');
      } else {
        // Fire-and-forget prefetch with bandwidth measurement.
        final sw = Stopwatch()..start();
        _filePreloadManager.prefetch(source).then((path) {
          sw.stop();
          if (path != null && !_disposed) {
            _bandwidthEstimator.addSample(
              2 * 1024 * 1024, // bytesToFetch default
              sw.elapsedMilliseconds,
            );
            _emit(BandwidthSampleEvent(
              bytesReceived: 2 * 1024 * 1024,
              durationMs: sw.elapsedMilliseconds,
              estimatedBytesPerSec:
                  _bandwidthEstimator.estimatedBytesPerSec ?? 0,
              concurrentDownloadsCount: 1,
            ));
          }
        });
      }
    }

    // Store the original source (not effectiveSource) so that
    // entry.currentSource.cacheKey always matches the logical cache key
    // for lock/unlock operations. The player receives effectiveSource
    // which may point to a local file path.
    entry.assignTo(index, source);
    try {
      final sw = Stopwatch()..start();
      await entry.adapter.swapSource(effectiveSource);
      sw.stop();
      _swapCount++;
      _emit(SwapEvent(
        entryId: entry.id,
        fromIndex: -1,
        toIndex: index,
        durationMs: sw.elapsedMilliseconds,
        isWarmStart: effectiveSource != source,
      ));
    } catch (e, st) {
      _logger.error('swapSource failed for entry ${entry.id}', e, st);
      _emit(ErrorEvent(
        code: 'SWAP_FAILED',
        message: 'swapSource failed for entry ${entry.id}: $e',
        fatal: false,
      ));
      if (_filePreloadManager != null) {
        _filePreloadManager.unlockKey(source.cacheKey);
      }
      entry.release();
      rethrow;
    }
  }

  /// Get the [PoolEntry] assigned to a specific [index], if any.
  PoolEntry? getEntryForIndex(int index) => _getEntryForIndex(index);

  /// Re-emit the last known visibility state.
  ///
  /// Useful when the app returns from background — the last playing video
  /// will be resumed without requiring a scroll event.
  ///
  /// Resets threshold state to force reconciliation even if the visibility
  /// hasn't changed since the last call.
  void resumeLastState() {
    if (_disposed || _lastPrimaryIndex < 0) return;
    final primary = _lastPrimaryIndex;
    final ratios = _lastVisibilityRatios;
    // Reset threshold state so onVisibilityChanged won't skip this call.
    _lastPlayableIndices = {};
    _lastPrimaryIndex = -1;
    onVisibilityChanged(
      primaryIndex: primary,
      visibilityRatios: ratios,
    );
  }

  /// Toggle play/pause for the video at [index].
  ///
  /// This goes through the pool (not directly mutating the entry) so that
  /// internal state tracking remains consistent.
  Future<void> togglePlayPause(int index) async {
    if (_disposed) return;
    final entry = _getEntryForIndex(index);
    if (entry == null) return;

    final state = entry.lifecycleState;
    if (state == LifecycleState.playing) {
      try {
        await entry.adapter.pause();
        entry.lifecycleNotifier.value = LifecycleState.paused;
      } catch (e, st) {
        _logger.error('Pause failed for index $index', e, st);
      }
    } else if (state == LifecycleState.paused ||
        state == LifecycleState.ready) {
      try {
        await entry.adapter.play();
        entry.lifecycleNotifier.value = LifecycleState.playing;
      } catch (e, st) {
        _logger.error('Play failed for index $index', e, st);
        entry.lifecycleNotifier.value = LifecycleState.error;
      }
    }
  }

  PoolEntry? _getEntryForIndex(int index) {
    for (final entry in _entries) {
      if (entry.isAssignedTo(index)) return entry;
    }
    return null;
  }

  /// Find an idle (unassigned) entry. Returns null if all are busy.
  PoolEntry? _findIdleEntry() {
    for (final entry in _entries) {
      if (entry.isIdle) return entry;
    }
    return null;
  }

  /// Get current pool statistics.
  PoolStatistics get statistics {
    var active = 0;
    var idle = 0;
    for (final entry in _entries) {
      if (entry.isIdle) {
        idle++;
      } else {
        active++;
      }
    }
    return PoolStatistics(
      totalCreated: _totalCreated,
      currentActive: active,
      currentIdle: idle,
      swapCount: _swapCount,
      disposeCount: _disposeCount,
      cacheHits: _cacheHits,
      cacheMisses: _cacheMisses,
      estimatedMemoryBytes: _memoryManager.currentUsageBytes,
    );
  }

  /// Handle device status changes (thermal + memory).
  ///
  /// Updates internal state and triggers emergency flush if needed.
  void onDeviceStatusChanged({
    required ThermalLevel thermalLevel,
    required MemoryPressureLevel memoryPressure,
  }) {
    if (_disposed) return;
    _thermalLevel = thermalLevel;
    _memoryPressure = memoryPressure;

    _emit(ThrottleEvent(
      thermalLevel: thermalLevel,
      memoryPressure: memoryPressure,
      effectiveMaxConcurrent: _orchestrator.computeEffectiveLimits(
        config: config,
        thermalLevel: thermalLevel,
        memoryPressure: memoryPressure,
      ).maxConcurrent,
    ));

    _memoryManager.scaleBudget(memoryPressure);

    if (memoryPressure == MemoryPressureLevel.terminal) {
      // Don't flush within the first 5 seconds of pool creation.
      // Some devices (e.g. MIUI on Redmi) aggressively report terminal
      // memory pressure on launch, which would destroy all entries before
      // any video starts playing.
      if (_warmupWatch.elapsedMilliseconds < 5000) {
        _logger.warning('Ignoring terminal pressure during pool warmup');
        return;
      }
      // Serialize emergency flush through the reconciliation chain to
      // prevent concurrent modification of entries.
      _activeReconciliation = (_activeReconciliation ?? Future<void>.value())
          .then((_) {
        if (!_disposed) return _emergencyFlush();
      });
    }

    // When pressure drops from terminal/critical to normal/warning,
    // attempt to recover disposed entries back to maxConcurrent.
    if (_memoryPressure == MemoryPressureLevel.normal ||
        _memoryPressure == MemoryPressureLevel.warning) {
      if (_entries.length < config.maxConcurrent) {
        _tryRecoverEntries();
      }
    }

    _logger.info(
      'Device status: thermal=$thermalLevel, memory=$memoryPressure',
    );
  }

  /// Attempt to recover pool entries after emergency flush.
  ///
  /// Creates new adapters to fill the pool back to [config.maxConcurrent]
  /// when memory pressure has subsided.
  void _tryRecoverEntries() {
    final toRecover = config.maxConcurrent - _entries.length;
    if (toRecover <= 0) return;

    _logger.info('Recovering $toRecover pool entries after pressure relief');

    for (var i = 0; i < toRecover; i++) {
      final id = _nextEntryId++;
      final adapter = _adapterFactory(id);
      final entry = PoolEntry(id: id, adapter: adapter);
      _entries.add(entry);
      _memoryManager.track(entry);
      _totalCreated++;
    }

    _logger.info(
      'Recovery complete. Pool now has ${_entries.length} entries',
    );

    // Re-reconcile with the last known visibility state so that
    // recovered entries are immediately put to use.
    // Reset threshold state to force reconciliation.
    if (_lastPrimaryIndex >= 0) {
      final primary = _lastPrimaryIndex;
      final ratios = _lastVisibilityRatios;
      _lastPlayableIndices = {};
      _lastPrimaryIndex = -1;
      onVisibilityChanged(
        primaryIndex: primary,
        visibilityRatios: ratios,
      );
    }
  }

  /// Emergency flush — dispose all except the primary player.
  ///
  /// Always keeps at least one entry alive to prevent the pool from
  /// becoming permanently empty (which would make the app appear dead).
  Future<void> _emergencyFlush() async {
    _logger.warning('Emergency flush triggered!');

    // Find the primary entry (the one currently playing).
    PoolEntry? primary;
    for (final entry in _entries) {
      if (entry.lifecycleState == LifecycleState.playing) {
        primary = entry;
        break;
      }
    }

    // If nothing is playing, keep the first entry alive so the pool
    // is never left completely empty.
    if (primary == null && _entries.isNotEmpty) {
      primary = _entries.first;
    }

    _logger.warning('Emergency flush! Keeping entry ${primary?.id}');

    final toEvict = _memoryManager.emergencyFlush(primary?.id);
    // Collect entries to remove (avoid modifying list while iterating).
    final toRemove = <PoolEntry>[];
    for (final entry in toEvict) {
      // Never dispose the kept entry.
      if (entry.id == primary?.id) continue;
      _logger.debug('Emergency disposing entry ${entry.id}');
      entry.lifecycleNotifier.value = LifecycleState.disposed;
      try {
        await entry.adapter.dispose();
      } catch (e, st) {
        _logger.error('Emergency dispose failed for entry ${entry.id}', e, st);
      }
      entry.disposeNotifier();
      _memoryManager.untrack(entry.id);
      toRemove.add(entry);
      _disposeCount++;
    }
    for (final entry in toRemove) {
      _entries.remove(entry);
    }

    _emit(EmergencyFlushEvent(
      survivorEntryId: primary?.id,
      disposedCount: toRemove.length,
    ));

    _logger.warning(
      'Emergency flush complete. Remaining entries: ${_entries.length}',
    );
  }

  /// Dispose all entries and shut down the pool.
  ///
  /// After calling this, the pool cannot be used again.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _eventController.close();

    _logger.info('Disposing pool with ${_entries.length} entries');
    reconciliationNotifier.dispose();

    // Copy to avoid concurrent modification if emergency flush already removed some.
    final remaining = List<PoolEntry>.of(_entries);
    _entries.clear();

    for (final entry in remaining) {
      try {
        if (entry.currentSource != null) {
          _filePreloadManager?.unlockKey(entry.currentSource!.cacheKey);
        }
        await entry.adapter.dispose();
        entry.disposeNotifier();
        _memoryManager.untrack(entry.id);
        _disposeCount++;
      } catch (e, st) {
        _logger.error('Dispose failed for entry ${entry.id}', e, st);
      }
    }

    await _filePreloadManager?.dispose();

    _logger.info('Pool disposed');
  }
}
