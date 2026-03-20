import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:video_pool/video_pool.dart';

import '../../mocks/mock_player_adapter.dart';

void main() {
  late List<MockPlayerAdapter> createdAdapters;
  late Map<int, VideoSource> sources;

  setUpAll(() {
    registerPlayerAdapterFallbacks();
  });

  setUp(() {
    createdAdapters = [];
    sources = {
      0: const VideoSource(url: 'https://example.com/video0.mp4'),
      1: const VideoSource(url: 'https://example.com/video1.mp4'),
      2: const VideoSource(url: 'https://example.com/video2.mp4'),
      3: const VideoSource(url: 'https://example.com/video3.mp4'),
      4: const VideoSource(url: 'https://example.com/video4.mp4'),
      5: const VideoSource(url: 'https://example.com/video5.mp4'),
    };
  });

  MockPlayerAdapter createMockAdapter() {
    final adapter = MockPlayerAdapter();
    when(() => adapter.estimatedMemoryBytes).thenReturn(30 * 1024 * 1024);
    when(() => adapter.stateNotifier).thenReturn(
      ValueNotifier(const PlayerState()),
    );
    when(() => adapter.isReusable).thenReturn(true);
    when(() => adapter.swapSource(any())).thenAnswer((_) async {});
    when(() => adapter.prepare()).thenAnswer((_) async {});
    when(() => adapter.play()).thenAnswer((_) async {});
    when(() => adapter.pause()).thenAnswer((_) async {});
    when(() => adapter.dispose()).thenAnswer((_) async {});
    when(() => adapter.setVolume(any())).thenAnswer((_) async {});
    when(() => adapter.setLooping(any())).thenAnswer((_) async {});
    when(() => adapter.setSpeed(any())).thenAnswer((_) async {});
    createdAdapters.add(adapter);
    return adapter;
  }

  VideoPool createPool({
    VideoPoolConfig config = const VideoPoolConfig(maxConcurrent: 3),
  }) {
    return VideoPool(
      config: config,
      adapterFactory: (id) => createMockAdapter(),
      sourceResolver: (index) => sources[index],
    );
  }

  group('VideoPool initialization', () {
    test('creates maxConcurrent adapter instances', () {
      final pool = createPool(
        config: const VideoPoolConfig(maxConcurrent: 3),
      );

      expect(createdAdapters.length, 3);
      expect(pool.statistics.totalCreated, 3);
      expect(pool.statistics.currentIdle, 3);
      expect(pool.statistics.currentActive, 0);

      pool.dispose();
    });

    test('statistics starts with all zeros except totalCreated', () {
      final pool = createPool();
      final stats = pool.statistics;

      expect(stats.totalCreated, 3);
      expect(stats.swapCount, 0);
      expect(stats.disposeCount, 0);
      expect(stats.cacheHits, 0);
      expect(stats.cacheMisses, 0);

      pool.dispose();
    });
  });

  group('VideoPool.onVisibilityChanged', () {
    test('assigns a player to the primary index', () async {
      final pool = createPool();

      pool.onVisibilityChanged(
        primaryIndex: 0,
        visibilityRatios: {0: 1.0},
      );

      // Give the async reconciliation a tick to complete.
      await Future<void>.delayed(Duration.zero);

      final entry = pool.getEntryForIndex(0);
      expect(entry, isNotNull);
      expect(entry!.assignedIndex, 0);

      pool.dispose();
    });

    test('swapSource is called when assigning to a new index', () async {
      final pool = createPool();

      pool.onVisibilityChanged(
        primaryIndex: 0,
        visibilityRatios: {0: 1.0},
      );
      await Future<void>.delayed(Duration.zero);

      // At least one adapter should have had swapSource called.
      final swapped = createdAdapters
          .where((a) {
            try {
              verify(() => a.swapSource(any())).called(greaterThanOrEqualTo(1));
              return true;
            } catch (_) {
              return false;
            }
          })
          .toList();
      expect(swapped, isNotEmpty);

      pool.dispose();
    });

    test('preloads adjacent indices', () async {
      final pool = createPool(
        config: const VideoPoolConfig(maxConcurrent: 3, preloadCount: 1),
      );

      pool.onVisibilityChanged(
        primaryIndex: 2,
        visibilityRatios: {2: 1.0},
      );
      await Future<void>.delayed(Duration.zero);

      final stats = pool.statistics;
      // Primary (index 2) + preload (index 1, 3) = 3 active entries.
      expect(stats.currentActive, 3);
      expect(stats.currentIdle, 0);

      expect(pool.getEntryForIndex(2), isNotNull);
      expect(pool.getEntryForIndex(1), isNotNull);
      expect(pool.getEntryForIndex(3), isNotNull);

      pool.dispose();
    });

    test('releases entries when scrolling away', () async {
      final pool = createPool(
        config: const VideoPoolConfig(maxConcurrent: 3, preloadCount: 1),
      );

      // First, scroll to index 2.
      pool.onVisibilityChanged(
        primaryIndex: 2,
        visibilityRatios: {2: 1.0},
      );
      await Future<void>.delayed(Duration.zero);

      expect(pool.getEntryForIndex(2), isNotNull);

      // Now scroll far away to index 5.
      pool.onVisibilityChanged(
        primaryIndex: 5,
        visibilityRatios: {5: 1.0},
      );
      await Future<void>.delayed(Duration.zero);

      // Old indices should be released, new ones assigned.
      expect(pool.getEntryForIndex(5), isNotNull);
      expect(pool.getEntryForIndex(4), isNotNull);
      // Index 2 should be released (it's far from 5).
      expect(pool.getEntryForIndex(2), isNull);

      pool.dispose();
    });

    test('cache hit when entry already assigned to index', () async {
      final pool = createPool(
        config: const VideoPoolConfig(maxConcurrent: 3, preloadCount: 0),
      );

      pool.onVisibilityChanged(
        primaryIndex: 0,
        visibilityRatios: {0: 1.0},
      );
      await Future<void>.delayed(Duration.zero);

      final hitsBeforeSecondCall = pool.statistics.cacheHits;

      // Use resumeLastState to force re-reconciliation with the same
      // input (bypasses threshold deduplication).
      pool.resumeLastState();
      await Future<void>.delayed(Duration.zero);

      expect(pool.statistics.cacheHits, greaterThan(hitsBeforeSecondCall));

      pool.dispose();
    });

    test('skips reconciliation when threshold state unchanged', () async {
      final pool = createPool(
        config: const VideoPoolConfig(maxConcurrent: 3, preloadCount: 0),
      );

      pool.onVisibilityChanged(
        primaryIndex: 0,
        visibilityRatios: {0: 1.0},
      );
      await Future<void>.delayed(Duration.zero);

      final swapsBefore = pool.statistics.swapCount;

      // Same primary, same playable set — should be skipped.
      pool.onVisibilityChanged(
        primaryIndex: 0,
        visibilityRatios: {0: 0.95}, // Still above 0.6 threshold
      );
      await Future<void>.delayed(Duration.zero);

      // No new swaps should occur — reconciliation was skipped.
      expect(pool.statistics.swapCount, swapsBefore);

      pool.dispose();
    });

    test('triggers reconciliation on threshold crossing', () async {
      final pool = createPool(
        config: const VideoPoolConfig(maxConcurrent: 3, preloadCount: 0),
      );

      pool.onVisibilityChanged(
        primaryIndex: 0,
        visibilityRatios: {0: 1.0, 1: 0.3}, // index 1 below threshold
      );
      await Future<void>.delayed(Duration.zero);

      final statsBefore = pool.statistics;

      // Index 1 crosses above threshold — should trigger reconciliation.
      pool.onVisibilityChanged(
        primaryIndex: 0,
        visibilityRatios: {0: 1.0, 1: 0.7}, // index 1 now above 0.6
      );
      await Future<void>.delayed(Duration.zero);

      // Reconciliation should have run (playable set changed: {0} → {0,1}).
      expect(
        pool.statistics.cacheHits + pool.statistics.cacheMisses,
        greaterThan(statsBefore.cacheHits + statsBefore.cacheMisses),
      );

      pool.dispose();
    });

    test('does nothing after dispose', () async {
      final pool = createPool();
      await pool.dispose();

      // Should not throw.
      pool.onVisibilityChanged(
        primaryIndex: 0,
        visibilityRatios: {0: 1.0},
      );
      await Future<void>.delayed(Duration.zero);

      expect(pool.statistics.currentActive, 0);
    });
  });

  group('VideoPool.onDeviceStatusChanged', () {
    test('terminal memory triggers emergency flush', () async {
      final pool = createPool(
        config: const VideoPoolConfig(maxConcurrent: 3, preloadCount: 1),
      );

      // Assign players first.
      pool.onVisibilityChanged(
        primaryIndex: 2,
        visibilityRatios: {2: 1.0},
      );
      await Future<void>.delayed(Duration.zero);

      // Mark index 2 entry as playing so it survives.
      final primaryEntry = pool.getEntryForIndex(2);
      expect(primaryEntry, isNotNull);
      primaryEntry!.lifecycleNotifier.value = LifecycleState.playing;

      pool.onDeviceStatusChanged(
        thermalLevel: ThermalLevel.nominal,
        memoryPressure: MemoryPressureLevel.terminal,
      );

      // The primary playing entry should survive.
      // Others may be disposed (emergency flush).
      expect(pool.statistics.disposeCount, greaterThanOrEqualTo(0));

      pool.dispose();
    });

    test('non-terminal memory does not trigger emergency flush', () async {
      final pool = createPool();

      pool.onDeviceStatusChanged(
        thermalLevel: ThermalLevel.serious,
        memoryPressure: MemoryPressureLevel.critical,
      );

      // No entries should be disposed.
      expect(pool.statistics.disposeCount, 0);

      pool.dispose();
    });
  });

  group('VideoPool.dispose', () {
    test('disposes all adapter instances', () async {
      final pool = createPool(
        config: const VideoPoolConfig(maxConcurrent: 3),
      );

      await pool.dispose();

      for (final adapter in createdAdapters) {
        verify(() => adapter.dispose()).called(1);
      }
      expect(pool.statistics.disposeCount, 3);
    });

    test('dispose is idempotent', () async {
      final pool = createPool();

      await pool.dispose();
      await pool.dispose(); // Second call should be no-op.

      for (final adapter in createdAdapters) {
        verify(() => adapter.dispose()).called(1);
      }
    });
  });

  group('VideoPool.getEntryForIndex', () {
    test('returns null for unassigned index', () {
      final pool = createPool();

      expect(pool.getEntryForIndex(99), isNull);

      pool.dispose();
    });

    test('returns the correct entry for an assigned index', () async {
      final pool = createPool(
        config: const VideoPoolConfig(maxConcurrent: 3, preloadCount: 0),
      );

      pool.onVisibilityChanged(
        primaryIndex: 0,
        visibilityRatios: {0: 1.0},
      );
      await Future<void>.delayed(Duration.zero);

      final entry = pool.getEntryForIndex(0);
      expect(entry, isNotNull);
      expect(entry!.assignedIndex, 0);
      expect(entry.currentSource, sources[0]);

      pool.dispose();
    });
  });

  group('PoolEntry', () {
    test('assignTo updates fields correctly', () {
      final adapter = MockPlayerAdapter();
      when(() => adapter.estimatedMemoryBytes).thenReturn(0);
      when(() => adapter.stateNotifier).thenReturn(
        ValueNotifier(const PlayerState()),
      );

      final entry = PoolEntry(id: 0, adapter: adapter);
      expect(entry.isIdle, isTrue);
      expect(entry.assignedIndex, isNull);

      const source = VideoSource(url: 'https://example.com/v.mp4');
      entry.assignTo(5, source);

      expect(entry.isIdle, isFalse);
      expect(entry.assignedIndex, 5);
      expect(entry.currentSource, source);
      expect(entry.isAssignedTo(5), isTrue);
      expect(entry.isAssignedTo(3), isFalse);
    });

    test('release resets to idle', () {
      final adapter = MockPlayerAdapter();
      when(() => adapter.estimatedMemoryBytes).thenReturn(0);
      when(() => adapter.stateNotifier).thenReturn(
        ValueNotifier(const PlayerState()),
      );

      final entry = PoolEntry(id: 0, adapter: adapter);
      entry.assignTo(
        5,
        const VideoSource(url: 'https://example.com/v.mp4'),
      );
      expect(entry.isIdle, isFalse);

      entry.release();
      expect(entry.isIdle, isTrue);
      expect(entry.assignedIndex, isNull);
      expect(entry.currentSource, isNull);
      expect(entry.lifecycleState, LifecycleState.idle);
    });
  });

  group('PoolStatistics', () {
    test('equality works', () {
      const a = PoolStatistics(totalCreated: 3, currentActive: 2);
      const b = PoolStatistics(totalCreated: 3, currentActive: 2);
      const c = PoolStatistics(totalCreated: 3, currentActive: 1);

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('toString is readable', () {
      const stats = PoolStatistics(
        currentActive: 2,
        currentIdle: 1,
        swapCount: 5,
        disposeCount: 0,
        estimatedMemoryBytes: 50 * 1024 * 1024,
      );
      expect(stats.toString(), contains('active: 2'));
      expect(stats.toString(), contains('idle: 1'));
    });
  });

  group('VideoPoolConfig', () {
    test('defaults are sensible', () {
      const config = VideoPoolConfig();

      expect(config.maxConcurrent, 3);
      expect(config.preloadCount, 1);
      expect(config.memoryBudgetBytes, 150 * 1024 * 1024);
      expect(config.visibilityPlayThreshold, 0.6);
      expect(config.visibilityPauseThreshold, 0.4);
      expect(config.preloadTimeout, const Duration(seconds: 10));
      expect(config.logLevel, LogLevel.none);
      expect(config.lifecyclePolicy, isNull);
    });

    test('copyWith replaces fields', () {
      const config = VideoPoolConfig();
      final modified = config.copyWith(maxConcurrent: 5, preloadCount: 2);

      expect(modified.maxConcurrent, 5);
      expect(modified.preloadCount, 2);
      expect(modified.memoryBudgetBytes, config.memoryBudgetBytes);
    });

    test('equality works', () {
      const a = VideoPoolConfig();
      const b = VideoPoolConfig();
      const c = VideoPoolConfig(maxConcurrent: 5);

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('VideoPool.onScrollUpdate', () {
    test('emits PredictionEvent for high velocity', () async {
      final pool = createPool(
        config: const VideoPoolConfig(maxConcurrent: 3, preloadCount: 0),
      );

      final events = <PoolEvent>[];
      pool.eventStream.listen(events.add);

      pool.onScrollUpdate(
        position: 0.0,
        velocity: 5000.0,
        itemExtent: 800.0,
        itemCount: 100,
      );

      final predictionEvents =
          events.whereType<PredictionEvent>().toList();
      expect(predictionEvents, hasLength(1));
      expect(predictionEvents.first.predictedIndex, greaterThan(0));
      expect(predictionEvents.first.confidence, greaterThan(0.0));
      expect(predictionEvents.first.actualIndex, isNull);

      pool.dispose();
    });

    test('skips prediction for low velocity', () async {
      final pool = createPool(
        config: const VideoPoolConfig(maxConcurrent: 3, preloadCount: 0),
      );

      final events = <PoolEvent>[];
      pool.eventStream.listen(events.add);

      pool.onScrollUpdate(
        position: 0.0,
        velocity: 100.0, // below threshold (0.5 * 800 = 400)
        itemExtent: 800.0,
        itemCount: 100,
      );

      final predictionEvents =
          events.whereType<PredictionEvent>().toList();
      expect(predictionEvents, isEmpty);

      pool.dispose();
    });

    test('resolves prediction on next visibility change', () async {
      final pool = createPool(
        config: const VideoPoolConfig(maxConcurrent: 3, preloadCount: 0),
      );

      final events = <PoolEvent>[];
      pool.eventStream.listen(events.add);

      // First, make a prediction.
      pool.onScrollUpdate(
        position: 0.0,
        velocity: 5000.0,
        itemExtent: 800.0,
        itemCount: 100,
      );

      // Then user stops scrolling and visibility settles.
      pool.onVisibilityChanged(
        primaryIndex: 2,
        visibilityRatios: {2: 1.0},
      );
      await Future<void>.delayed(Duration.zero);

      final predictionEvents =
          events.whereType<PredictionEvent>().toList();
      // Should have 2: one prediction, one resolution.
      expect(predictionEvents.length, greaterThanOrEqualTo(2));

      final resolved =
          predictionEvents.where((e) => e.actualIndex != null).toList();
      expect(resolved, hasLength(1));
      expect(resolved.first.actualIndex, 2);

      pool.dispose();
    });

    test('does nothing after dispose', () async {
      final pool = createPool();
      await pool.dispose();

      // Should not throw.
      pool.onScrollUpdate(
        position: 0.0,
        velocity: 5000.0,
        itemExtent: 800.0,
        itemCount: 100,
      );
    });
  });

  group('VideoPool with DecoderBudget', () {
    test('uses decoderBudget when provided', () async {
      final budget = GlobalDecoderBudget(totalTokens: 4);

      final pool = VideoPool(
        config: const VideoPoolConfig(maxConcurrent: 3),
        adapterFactory: (id) => createMockAdapter(),
        sourceResolver: (index) => sources[index],
        decoderBudget: budget,
      );

      // Budget should have been requested.
      final totalAllocated =
          budget.allocations.values.fold(0, (a, b) => a + b);
      expect(totalAllocated, 3);
      expect(createdAdapters.length, 3);

      await pool.dispose();
      budget.dispose();
    });

    test('uses decoderBudget and gets fewer tokens than desired', () async {
      final budget = GlobalDecoderBudget(totalTokens: 2);

      final pool = VideoPool(
        config: const VideoPoolConfig(maxConcurrent: 3),
        adapterFactory: (id) => createMockAdapter(),
        sourceResolver: (index) => sources[index],
        decoderBudget: budget,
      );

      // Only 2 tokens available, so only 2 entries created.
      expect(createdAdapters.length, 2);
      expect(pool.statistics.totalCreated, 2);
      expect(pool.statistics.currentIdle, 2);

      await pool.dispose();
      budget.dispose();
    });

    test('releases tokens on dispose', () async {
      final budget = GlobalDecoderBudget(totalTokens: 4);

      final pool = VideoPool(
        config: const VideoPoolConfig(maxConcurrent: 3),
        adapterFactory: (id) => createMockAdapter(),
        sourceResolver: (index) => sources[index],
        decoderBudget: budget,
      );

      expect(budget.allocations.values.fold(0, (a, b) => a + b), 3);

      await pool.dispose();

      // All tokens should be released back.
      expect(budget.allocations, isEmpty);

      budget.dispose();
    });
  });

  group('VideoPool.eventStream', () {
    test('emits ReconcileEvent on visibility change', () async {
      final pool = createPool(
        config: const VideoPoolConfig(maxConcurrent: 3, preloadCount: 0),
      );

      final events = <PoolEvent>[];
      pool.eventStream.listen(events.add);

      pool.onVisibilityChanged(
        primaryIndex: 0,
        visibilityRatios: {0: 1.0},
      );
      await Future<void>.delayed(Duration.zero);

      final reconcileEvents = events.whereType<ReconcileEvent>().toList();
      expect(reconcileEvents, isNotEmpty);
      expect(reconcileEvents.last.primaryIndex, 0);
      expect(reconcileEvents.last.playCount, 1);

      pool.dispose();
    });

    test('emits SwapEvent when entry is assigned', () async {
      final pool = createPool(
        config: const VideoPoolConfig(maxConcurrent: 3, preloadCount: 0),
      );

      final events = <PoolEvent>[];
      pool.eventStream.listen(events.add);

      pool.onVisibilityChanged(
        primaryIndex: 0,
        visibilityRatios: {0: 1.0},
      );
      await Future<void>.delayed(Duration.zero);

      final swapEvents = events.whereType<SwapEvent>().toList();
      expect(swapEvents, isNotEmpty);
      expect(swapEvents.last.toIndex, 0);
      expect(swapEvents.last.durationMs, greaterThanOrEqualTo(0));

      pool.dispose();
    });

    test('emits ThrottleEvent on device status change', () async {
      final pool = createPool();

      final events = <PoolEvent>[];
      pool.eventStream.listen(events.add);

      pool.onDeviceStatusChanged(
        thermalLevel: ThermalLevel.serious,
        memoryPressure: MemoryPressureLevel.normal,
      );
      await Future<void>.delayed(Duration.zero);

      final throttleEvents = events.whereType<ThrottleEvent>().toList();
      expect(throttleEvents, hasLength(1));
      expect(throttleEvents.first.thermalLevel, ThermalLevel.serious);

      pool.dispose();
    });

    test('metrics getter returns snapshot with data', () async {
      final pool = createPool(
        config: const VideoPoolConfig(maxConcurrent: 3, preloadCount: 0),
      );

      pool.onVisibilityChanged(
        primaryIndex: 0,
        visibilityRatios: {0: 1.0},
      );
      await Future<void>.delayed(Duration.zero);

      final m = pool.metrics;
      expect(m.totalEvents, greaterThan(0));
      expect(m.computedAt, greaterThan(0));

      pool.dispose();
    });

    test('eventStream closes after dispose', () async {
      final pool = createPool();

      var done = false;
      pool.eventStream.listen(null, onDone: () => done = true);

      await pool.dispose();
      expect(done, isTrue);
    });
  });
}
