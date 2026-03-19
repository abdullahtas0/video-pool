import '../adapter/player_adapter.dart';
import '../lifecycle/lifecycle_orchestrator.dart';
import '../lifecycle/lifecycle_policy.dart';
import '../lifecycle/lifecycle_state.dart';
import '../memory/memory_manager.dart';
import '../memory/memory_pressure_level.dart';
import '../models/thermal_status.dart';
import '../models/video_source.dart';
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
  VideoPool({
    required this.config,
    required PlayerAdapter Function(int id) adapterFactory,
    required VideoSourceResolver sourceResolver,
  })  : _sourceResolver = sourceResolver,
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
    for (var i = 0; i < config.maxConcurrent; i++) {
      final adapter = adapterFactory(i);
      final entry = PoolEntry(id: i, adapter: adapter);
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

  // --- Statistics counters ---
  int _totalCreated = 0;
  int _swapCount = 0;
  int _disposeCount = 0;
  int _cacheHits = 0;
  int _cacheMisses = 0;

  // --- Device state ---
  ThermalLevel _thermalLevel = ThermalLevel.nominal;
  MemoryPressureLevel _memoryPressure = MemoryPressureLevel.normal;

  /// Called by the visibility tracker when viewport changes.
  ///
  /// [primaryIndex] is the most visible slot index.
  /// [visibilityRatios] maps visible slot indices to their visibility (0.0–1.0).
  void onVisibilityChanged({
    required int primaryIndex,
    required Map<int, double> visibilityRatios,
  }) {
    if (_disposed) return;
    _reconcile(primaryIndex, visibilityRatios);
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
      if (_getEntryForIndex(index) != null) {
        // Already assigned — cache hit.
        _cacheHits++;
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
  }

  /// Release a player from its current assignment back to the idle pool.
  ///
  /// The adapter is NOT disposed — it remains available for reuse.
  Future<void> _releaseEntry(PoolEntry entry) async {
    _logger.debug('Releasing entry ${entry.id} from index ${entry.assignedIndex}');
    try {
      await entry.adapter.pause();
    } catch (e, st) {
      _logger.error('Pause during release failed for entry ${entry.id}', e, st);
    }
    entry.release();
  }

  /// Assign an idle entry to a new video index via [swapSource].
  Future<void> _assignEntry(
    PoolEntry entry,
    int index,
    VideoSource source,
  ) async {
    _logger.debug('Assigning entry ${entry.id} to index $index');
    entry.assignTo(index, source);
    try {
      await entry.adapter.swapSource(source);
      _swapCount++;
    } catch (e, st) {
      _logger.error('swapSource failed for entry ${entry.id}', e, st);
      entry.release();
      rethrow;
    }
  }

  /// Get the [PoolEntry] assigned to a specific [index], if any.
  PoolEntry? getEntryForIndex(int index) => _getEntryForIndex(index);

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

    _memoryManager.scaleBudget(memoryPressure);

    if (memoryPressure == MemoryPressureLevel.terminal) {
      _emergencyFlush();
    }

    _logger.info(
      'Device status: thermal=$thermalLevel, memory=$memoryPressure',
    );
  }

  /// Emergency flush — dispose all except the primary player.
  void _emergencyFlush() {
    _logger.warning('Emergency flush triggered!');

    // Find the primary entry (the one currently playing).
    PoolEntry? primary;
    for (final entry in _entries) {
      if (entry.lifecycleState == LifecycleState.playing) {
        primary = entry;
        break;
      }
    }

    final toEvict = _memoryManager.emergencyFlush(primary?.id);
    for (final entry in toEvict) {
      if (entry.lifecycleState != LifecycleState.playing) {
        _logger.debug('Emergency disposing entry ${entry.id}');
        entry.lifecycleNotifier.value = LifecycleState.disposed;
        entry.adapter.dispose();
        _memoryManager.untrack(entry.id);
        _entries.remove(entry);
        _disposeCount++;
      }
    }

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

    _logger.info('Disposing pool with ${_entries.length} entries');

    for (final entry in _entries) {
      try {
        await entry.adapter.dispose();
        entry.disposeNotifier();
        _memoryManager.untrack(entry.id);
        _disposeCount++;
      } catch (e, st) {
        _logger.error('Dispose failed for entry ${entry.id}', e, st);
      }
    }
    _entries.clear();

    _logger.info('Pool disposed');
  }
}
