import '../memory/memory_pressure_level.dart';
import '../models/thermal_status.dart';
import '../pool/pool_config.dart';
import '../pool/video_pool_logger.dart';
import 'lifecycle_policy.dart';

/// Effective resource limits computed from config + device conditions.
typedef EffectiveLimits = ({
  int maxConcurrent,
  int preloadCount,
  int memoryBudget,
});

/// The reconciliation engine that decides what each player slot should do.
///
/// Delegates to a [LifecyclePolicy] for the actual decision logic, but adds
/// device-condition-aware limit computation on top.
class LifecycleOrchestrator {
  /// Creates a [LifecycleOrchestrator] with the given [policy] and [logger].
  LifecycleOrchestrator({
    required this.policy,
    required this.logger,
  });

  /// The lifecycle policy that determines reconciliation behavior.
  final LifecyclePolicy policy;

  /// Logger for diagnostic output.
  final VideoPoolLogger logger;

  /// Called when visibility changes. Computes what each slot should do.
  ///
  /// Returns a [ReconciliationPlan] describing which slots to play, pause,
  /// preload, or release.
  ReconciliationPlan reconcile({
    required int primaryIndex,
    required Map<int, double> visibilityRatios,
    required int effectiveMaxConcurrent,
    required int effectivePreloadCount,
    required Set<int> currentlyActive,
  }) {
    logger.debug(
      'Reconcile: primary=$primaryIndex, '
      'visible=${visibilityRatios.keys.toList()}, '
      'active=${currentlyActive.toList()}, '
      'maxConcurrent=$effectiveMaxConcurrent, '
      'preloadCount=$effectivePreloadCount',
    );

    final plan = policy.reconcile(
      primaryIndex: primaryIndex,
      visibilityRatios: visibilityRatios,
      effectiveMaxConcurrent: effectiveMaxConcurrent,
      effectivePreloadCount: effectivePreloadCount,
      currentlyActive: currentlyActive,
    );

    logger.debug('Plan: $plan');
    return plan;
  }

  /// Compute effective resource limits based on thermal and memory conditions.
  ///
  /// Higher thermal levels or memory pressure reduce the limits so the pool
  /// uses fewer resources under stress.
  EffectiveLimits computeEffectiveLimits({
    required VideoPoolConfig config,
    required ThermalLevel thermalLevel,
    required MemoryPressureLevel memoryPressure,
  }) {
    var maxConcurrent = config.maxConcurrent;
    var preloadCount = config.preloadCount;
    var memoryBudget = config.memoryBudgetBytes;

    // Thermal throttling.
    switch (thermalLevel) {
      case ThermalLevel.nominal:
        break; // No change.
      case ThermalLevel.fair:
        // Slight reduction: drop preload by 1 if possible.
        preloadCount = (preloadCount - 1).clamp(0, preloadCount);
      case ThermalLevel.serious:
        // Significant: halve concurrent, no preload.
        maxConcurrent = (maxConcurrent ~/ 2).clamp(1, maxConcurrent);
        preloadCount = 0;
      case ThermalLevel.critical:
        // Emergency: only 1 player, no preload.
        maxConcurrent = 1;
        preloadCount = 0;
    }

    // Memory pressure further reduces limits.
    switch (memoryPressure) {
      case MemoryPressureLevel.normal:
        break;
      case MemoryPressureLevel.warning:
        preloadCount = 0;
        memoryBudget = (memoryBudget * 0.75).round();
      case MemoryPressureLevel.critical:
        maxConcurrent = (maxConcurrent ~/ 2).clamp(1, maxConcurrent);
        preloadCount = 0;
        memoryBudget = (memoryBudget * 0.50).round();
      case MemoryPressureLevel.terminal:
        maxConcurrent = 1;
        preloadCount = 0;
        memoryBudget = (memoryBudget * 0.25).round();
    }

    logger.debug(
      'Effective limits: maxConcurrent=$maxConcurrent, '
      'preloadCount=$preloadCount, '
      'memoryBudget=${memoryBudget ~/ (1024 * 1024)}MB '
      '(thermal=$thermalLevel, memory=$memoryPressure)',
    );

    return (
      maxConcurrent: maxConcurrent,
      preloadCount: preloadCount,
      memoryBudget: memoryBudget,
    );
  }
}
