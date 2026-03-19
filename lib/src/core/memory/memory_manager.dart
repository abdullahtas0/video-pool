import '../pool/pool_entry.dart';
import '../pool/video_pool_logger.dart';
import 'memory_pressure_level.dart';

/// Manages memory tracking and eviction for the video pool.
///
/// Uses an internal map to track [PoolEntry] memory usage and provides
/// LRU-based eviction candidates when the memory budget is exceeded.
class MemoryManager {
  /// Creates a [MemoryManager] with the given byte budget.
  MemoryManager({
    required this.budgetBytes,
    VideoPoolLogger? logger,
  })  : assert(budgetBytes > 0, 'budgetBytes must be positive'),
        _logger = logger ?? const VideoPoolLogger(),
        _effectiveBudgetBytes = budgetBytes;

  /// The base memory budget in bytes.
  final int budgetBytes;

  final VideoPoolLogger _logger;

  /// The effective budget after scaling for memory pressure.
  int _effectiveBudgetBytes;

  /// Tracked entries keyed by entry ID.
  final Map<int, PoolEntry> _entries = {};

  /// The current effective memory budget (may differ from [budgetBytes]
  /// when scaled due to memory pressure).
  int get effectiveBudgetBytes => _effectiveBudgetBytes;

  /// Register an entry for memory tracking.
  void track(PoolEntry entry) {
    _entries[entry.id] = entry;
    _logger.debug(
      'Tracking entry ${entry.id}, '
      'estimated ${entry.adapter.estimatedMemoryBytes} bytes',
    );
  }

  /// Stop tracking an entry.
  void untrack(int entryId) {
    _entries.remove(entryId);
    _logger.debug('Untracked entry $entryId');
  }

  /// Total estimated memory usage of all tracked entries.
  int get currentUsageBytes {
    var total = 0;
    for (final entry in _entries.values) {
      total += entry.adapter.estimatedMemoryBytes;
    }
    return total;
  }

  /// Whether adding [additionalBytes] would exceed the effective budget.
  bool wouldExceedBudget(int additionalBytes) {
    return currentUsageBytes + additionalBytes > _effectiveBudgetBytes;
  }

  /// Get entries to evict in LRU order to free at least [targetBytes].
  ///
  /// Only idle (unassigned) entries are considered for eviction.
  /// Returns entries ordered from least recently used to most recent.
  List<PoolEntry> getEvictionCandidates(int targetBytes) {
    // Sort idle entries by lastUsed (oldest first).
    final idleEntries = _entries.values
        .where((e) => e.isIdle)
        .toList()
      ..sort((a, b) => a.lastUsed.compareTo(b.lastUsed));

    final candidates = <PoolEntry>[];
    var freedBytes = 0;

    for (final entry in idleEntries) {
      if (freedBytes >= targetBytes) break;
      candidates.add(entry);
      freedBytes += entry.adapter.estimatedMemoryBytes;
    }

    _logger.debug(
      'Eviction candidates: ${candidates.length} entries, '
      'would free $freedBytes bytes (target: $targetBytes)',
    );
    return candidates;
  }

  /// Scale the effective budget based on memory pressure.
  ///
  /// - [MemoryPressureLevel.normal]: 100% of budget
  /// - [MemoryPressureLevel.warning]: 75% of budget
  /// - [MemoryPressureLevel.critical]: 50% of budget
  /// - [MemoryPressureLevel.terminal]: 25% of budget
  void scaleBudget(MemoryPressureLevel level) {
    final scale = switch (level) {
      MemoryPressureLevel.normal => 1.0,
      MemoryPressureLevel.warning => 0.75,
      MemoryPressureLevel.critical => 0.50,
      MemoryPressureLevel.terminal => 0.25,
    };

    _effectiveBudgetBytes = (budgetBytes * scale).round();
    _logger.info(
      'Memory budget scaled to ${(_effectiveBudgetBytes / (1024 * 1024)).toStringAsFixed(1)}MB '
      '(pressure: $level)',
    );
  }

  /// Emergency flush: return all entries except [primaryEntryId] for eviction.
  ///
  /// Used when memory pressure is terminal. Returns entries that should
  /// be disposed immediately.
  List<PoolEntry> emergencyFlush(int? primaryEntryId) {
    _logger.warning('Emergency flush! Keeping only entry $primaryEntryId');

    return _entries.values
        .where((e) => e.id != primaryEntryId)
        .toList();
  }

  /// Reset effective budget to the base budget.
  void resetBudget() {
    _effectiveBudgetBytes = budgetBytes;
  }
}
