import 'package:flutter_test/flutter_test.dart';
import 'package:video_pool/video_pool.dart';

void main() {
  late LifecycleOrchestrator orchestrator;

  setUp(() {
    orchestrator = LifecycleOrchestrator(
      policy: const DefaultLifecyclePolicy(),
      logger: const VideoPoolLogger(level: LogLevel.none),
    );
  });

  group('LifecycleOrchestrator.reconcile', () {
    test('plays primary index and preloads adjacent', () {
      final plan = orchestrator.reconcile(
        primaryIndex: 5,
        visibilityRatios: {5: 1.0},
        effectiveMaxConcurrent: 3,
        effectivePreloadCount: 1,
        currentlyActive: {},
      );

      expect(plan.toPlay, {5});
      expect(plan.toPreload, containsAll([4, 6]));
      expect(plan.toRelease, isEmpty);
    });

    test('releases entries beyond max concurrent', () {
      final plan = orchestrator.reconcile(
        primaryIndex: 5,
        visibilityRatios: {5: 1.0, 3: 0.2, 4: 0.5},
        effectiveMaxConcurrent: 2,
        effectivePreloadCount: 1,
        currentlyActive: {3, 4, 5},
      );

      expect(plan.toPlay, {5});
      // With maxConcurrent=2 and preload=1, we can have primary + 1 more.
      // Index 6 is preloaded but 4 is also preloaded.
      // The furthest from primary (3) should be released.
      expect(plan.toRelease, contains(3));
    });

    test('releases currently active slots that are no longer needed', () {
      final plan = orchestrator.reconcile(
        primaryIndex: 10,
        visibilityRatios: {10: 1.0},
        effectiveMaxConcurrent: 3,
        effectivePreloadCount: 1,
        currentlyActive: {5, 6, 7}, // These are far from primary index 10.
      );

      expect(plan.toPlay, {10});
      expect(plan.toRelease, containsAll([5, 6, 7]));
    });

    test('pauses visible but non-primary slots', () {
      final plan = orchestrator.reconcile(
        primaryIndex: 5,
        visibilityRatios: {4: 0.3, 5: 1.0, 6: 0.3},
        effectiveMaxConcurrent: 5,
        effectivePreloadCount: 0,
        currentlyActive: {4, 5, 6},
      );

      expect(plan.toPlay, {5});
      expect(plan.toPause, containsAll([4, 6]));
    });

    test('handles primary at index 0 (no negative preload)', () {
      final plan = orchestrator.reconcile(
        primaryIndex: 0,
        visibilityRatios: {0: 1.0},
        effectiveMaxConcurrent: 3,
        effectivePreloadCount: 1,
        currentlyActive: {},
      );

      expect(plan.toPlay, {0});
      expect(plan.toPreload, {1}); // Only forward preload, no negative indices.
    });

    test('handles empty visibility ratios', () {
      final plan = orchestrator.reconcile(
        primaryIndex: 0,
        visibilityRatios: {},
        effectiveMaxConcurrent: 3,
        effectivePreloadCount: 1,
        currentlyActive: {},
      );

      expect(plan.toPlay, {0});
      expect(plan.toPreload.isNotEmpty, isTrue);
    });
  });

  group('LifecycleOrchestrator.computeEffectiveLimits', () {
    const baseConfig = VideoPoolConfig(
      maxConcurrent: 4,
      preloadCount: 2,
      memoryBudgetBytes: 200 * 1024 * 1024,
    );

    test('nominal thermal + normal memory = no reduction', () {
      final limits = orchestrator.computeEffectiveLimits(
        config: baseConfig,
        thermalLevel: ThermalLevel.nominal,
        memoryPressure: MemoryPressureLevel.normal,
      );

      expect(limits.maxConcurrent, 4);
      expect(limits.preloadCount, 2);
      expect(limits.memoryBudget, 200 * 1024 * 1024);
    });

    test('fair thermal reduces preload by 1', () {
      final limits = orchestrator.computeEffectiveLimits(
        config: baseConfig,
        thermalLevel: ThermalLevel.fair,
        memoryPressure: MemoryPressureLevel.normal,
      );

      expect(limits.maxConcurrent, 4);
      expect(limits.preloadCount, 1);
    });

    test('serious thermal halves concurrent and disables preload', () {
      final limits = orchestrator.computeEffectiveLimits(
        config: baseConfig,
        thermalLevel: ThermalLevel.serious,
        memoryPressure: MemoryPressureLevel.normal,
      );

      expect(limits.maxConcurrent, 2);
      expect(limits.preloadCount, 0);
    });

    test('critical thermal = 1 concurrent, no preload', () {
      final limits = orchestrator.computeEffectiveLimits(
        config: baseConfig,
        thermalLevel: ThermalLevel.critical,
        memoryPressure: MemoryPressureLevel.normal,
      );

      expect(limits.maxConcurrent, 1);
      expect(limits.preloadCount, 0);
    });

    test('warning memory disables preload and reduces budget', () {
      final limits = orchestrator.computeEffectiveLimits(
        config: baseConfig,
        thermalLevel: ThermalLevel.nominal,
        memoryPressure: MemoryPressureLevel.warning,
      );

      expect(limits.maxConcurrent, 4);
      expect(limits.preloadCount, 0);
      expect(limits.memoryBudget, (200 * 1024 * 1024 * 0.75).round());
    });

    test('critical memory halves concurrent', () {
      final limits = orchestrator.computeEffectiveLimits(
        config: baseConfig,
        thermalLevel: ThermalLevel.nominal,
        memoryPressure: MemoryPressureLevel.critical,
      );

      expect(limits.maxConcurrent, 2);
      expect(limits.preloadCount, 0);
    });

    test('terminal memory = 1 concurrent, 25% budget', () {
      final limits = orchestrator.computeEffectiveLimits(
        config: baseConfig,
        thermalLevel: ThermalLevel.nominal,
        memoryPressure: MemoryPressureLevel.terminal,
      );

      expect(limits.maxConcurrent, 1);
      expect(limits.preloadCount, 0);
      expect(limits.memoryBudget, (200 * 1024 * 1024 * 0.25).round());
    });

    test('combined thermal + memory applies both reductions', () {
      final limits = orchestrator.computeEffectiveLimits(
        config: baseConfig,
        thermalLevel: ThermalLevel.serious,
        memoryPressure: MemoryPressureLevel.critical,
      );

      // Serious thermal: maxConcurrent=2, preload=0
      // Critical memory: maxConcurrent halved again = 1
      expect(limits.maxConcurrent, 1);
      expect(limits.preloadCount, 0);
    });

    test('maxConcurrent never goes below 1', () {
      final limits = orchestrator.computeEffectiveLimits(
        config: const VideoPoolConfig(maxConcurrent: 1, preloadCount: 0),
        thermalLevel: ThermalLevel.critical,
        memoryPressure: MemoryPressureLevel.terminal,
      );

      expect(limits.maxConcurrent, 1);
    });
  });
}
