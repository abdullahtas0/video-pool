import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:video_pool/video_pool.dart';

import '../mocks/mock_player_adapter.dart';

void main() {
  late List<MockPlayerAdapter> createdAdapters;
  late List<VideoSource> sources;

  setUpAll(() {
    registerPlayerAdapterFallbacks();
  });

  setUp(() {
    createdAdapters = [];
    sources = [
      const VideoSource(url: 'https://example.com/video0.mp4'),
      const VideoSource(url: 'https://example.com/video1.mp4'),
      const VideoSource(url: 'https://example.com/video2.mp4'),
      const VideoSource(url: 'https://example.com/video3.mp4'),
      const VideoSource(url: 'https://example.com/video4.mp4'),
    ];
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
    when(() => adapter.videoWidget).thenReturn(const SizedBox());
    when(() => adapter.position).thenReturn(Duration.zero);
    when(() => adapter.duration).thenReturn(Duration.zero);
    createdAdapters.add(adapter);
    return adapter;
  }

  VideoPool createPool({
    VideoPoolConfig config = const VideoPoolConfig(maxConcurrent: 3),
    DecoderBudget? decoderBudget,
  }) {
    return VideoPool(
      config: config,
      adapterFactory: (id) => createMockAdapter(),
      sourceResolver: (index) =>
          index >= 0 && index < sources.length ? sources[index] : null,
      decoderBudget: decoderBudget,
    );
  }

  group('Full lifecycle: scope → feed → scroll → reconcile → events', () {
    test('creates pool, triggers visibility, scrolls, and emits events',
        () async {
      final events = <PoolEvent>[];

      final pool = createPool(
        config: const VideoPoolConfig(maxConcurrent: 3, preloadCount: 1),
      );
      final subscription = pool.eventStream.listen(events.add);

      // Pool should be initialized with 3 adapters.
      expect(createdAdapters.length, 3);
      expect(pool.statistics.totalCreated, 3);
      expect(pool.statistics.currentIdle, 3);
      expect(pool.statistics.currentActive, 0);

      // Simulate what VideoFeedView does: notify visibility for page 0.
      pool.onVisibilityChanged(
        primaryIndex: 0,
        visibilityRatios: {0: 1.0},
      );
      await Future<void>.delayed(Duration.zero);

      // Initial reconciliation should have emitted a ReconcileEvent.
      expect(
        events.whereType<ReconcileEvent>(),
        isNotEmpty,
        reason: 'Expected ReconcileEvent after initial visibility',
      );

      // Entry for index 0 should be assigned.
      expect(pool.getEntryForIndex(0), isNotNull);
      expect(pool.statistics.currentActive, greaterThanOrEqualTo(1));

      // SwapEvent should have been emitted for assigning the adapter.
      expect(
        events.whereType<SwapEvent>(),
        isNotEmpty,
        reason: 'Expected SwapEvent when adapter is assigned',
      );

      // Simulate scrolling to page 2 (like a fling in VideoFeedView).
      pool.onVisibilityChanged(
        primaryIndex: 2,
        visibilityRatios: {2: 1.0},
      );
      await Future<void>.delayed(Duration.zero);

      // Verify multiple ReconcileEvents exist (initial + scroll).
      final reconcileEvents = events.whereType<ReconcileEvent>().toList();
      expect(reconcileEvents.length, greaterThanOrEqualTo(2),
          reason: 'Expected reconciliation for initial page and after scroll');

      // Second reconcile should target primary index 2.
      expect(reconcileEvents.last.primaryIndex, 2);

      // Entry for index 2 should now be assigned.
      expect(pool.getEntryForIndex(2), isNotNull);

      await subscription.cancel();
      await pool.dispose();
    });

    testWidgets('VideoFeedView renders and pool interacts via provider',
        (tester) async {
      // Create pool with simple config and trigger reconciliation
      // before mounting the widget (avoids async pump hanging).
      final pool = createPool(
        config: const VideoPoolConfig(maxConcurrent: 1, preloadCount: 0),
      );

      pool.onVisibilityChanged(
        primaryIndex: 0,
        visibilityRatios: {0: 1.0},
      );
      await tester.pumpAndSettle();

      // Verify entry is assigned before widget mount.
      expect(pool.getEntryForIndex(0), isNotNull);

      await tester.pumpWidget(
        MaterialApp(
          home: VideoPoolProvider(
            pool: pool,
            child: VideoFeedView(
              sources: sources,
              itemBuilder: (context, index, source) {
                return SizedBox.expand(
                  child: Center(child: Text('Video $index')),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // Verify the VideoFeedView and PageView are rendered.
      expect(find.byType(VideoFeedView), findsOneWidget);
      expect(find.byType(PageView), findsOneWidget);
      expect(find.text('Video 0'), findsOneWidget);

      await pool.dispose();
    });
  });

  group('Tab switch pauses and resumes pool', () {
    test('switching tabs pauses and resumes pool', () async {
      final pool = createPool(
        config: const VideoPoolConfig(maxConcurrent: 3, preloadCount: 1),
      );

      // Start with primary index 0.
      pool.onVisibilityChanged(
        primaryIndex: 0,
        visibilityRatios: {0: 1.0},
      );
      await Future<void>.delayed(Duration.zero);

      // Verify entry is assigned to index 0.
      expect(pool.getEntryForIndex(0), isNotNull);
      expect(pool.statistics.currentActive, greaterThanOrEqualTo(1));

      // Simulate tab switch away: primary = -1 (no video visible).
      pool.onVisibilityChanged(
        primaryIndex: -1,
        visibilityRatios: const {},
      );
      await Future<void>.delayed(Duration.zero);

      // After primary=-1, the reconciliation should release entries.
      final events = <PoolEvent>[];
      final sub = pool.eventStream.listen(events.add);

      // Simulate tab switch back: set primary back to 0.
      pool.onVisibilityChanged(
        primaryIndex: 0,
        visibilityRatios: {0: 1.0},
      );
      await Future<void>.delayed(Duration.zero);

      expect(pool.getEntryForIndex(0), isNotNull,
          reason: 'Pool should resume after tab switch back');

      // Verify a ReconcileEvent was emitted for the resume.
      expect(
        events.whereType<ReconcileEvent>(),
        isNotEmpty,
        reason: 'ReconcileEvent should be emitted on tab switch back',
      );

      await sub.cancel();
      await pool.dispose();
    });
  });

  group('VideoListView mixed content with visibility tracking', () {
    test('visibility changes trigger reconciliation for different indices',
        () async {
      final events = <PoolEvent>[];
      final pool = createPool(
        config: const VideoPoolConfig(maxConcurrent: 3, preloadCount: 1),
      );
      final subscription = pool.eventStream.listen(events.add);

      // Simulate initial visibility (what VideoListView postFrameCallback does).
      pool.onVisibilityChanged(
        primaryIndex: 0,
        visibilityRatios: {0: 1.0, 1: 0.5, 2: 0.3},
      );
      await Future<void>.delayed(Duration.zero);

      // Initial visibility should have triggered reconciliation.
      expect(
        events.whereType<ReconcileEvent>(),
        isNotEmpty,
        reason: 'Initial visibility should trigger reconciliation',
      );

      // Pool should have assigned entries.
      expect(pool.statistics.currentActive, greaterThanOrEqualTo(1),
          reason: 'At least one entry should be active');

      // Simulate scroll down: new indices become visible.
      pool.onVisibilityChanged(
        primaryIndex: 2,
        visibilityRatios: {2: 1.0, 3: 0.5},
      );
      await Future<void>.delayed(Duration.zero);

      // After scrolling, we should have additional reconciliation events.
      final reconcileCount = events.whereType<ReconcileEvent>().length;
      expect(reconcileCount, greaterThanOrEqualTo(2),
          reason: 'Scroll should trigger additional reconciliation');

      // Entry for new primary index should be assigned.
      expect(pool.getEntryForIndex(2), isNotNull);

      await subscription.cancel();
      await pool.dispose();
    });

    testWidgets('VideoListView renders with mixed content items',
        (tester) async {
      final pool = createPool(
        config: const VideoPoolConfig(maxConcurrent: 1, preloadCount: 0),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: VideoPoolProvider(
            pool: pool,
            child: VideoListView(
              itemCount: 5,
              itemExtent: 200,
              itemBuilder: (context, index) {
                if (index.isEven) {
                  return SizedBox(
                    height: 200,
                    child: Center(child: Text('Video $index')),
                  );
                }
                return SizedBox(
                  height: 200,
                  child: Center(child: Text('Text post $index')),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // Verify the VideoListView and ListView are rendered.
      expect(find.byType(VideoListView), findsOneWidget);
      expect(find.byType(ListView), findsOneWidget);
      expect(find.text('Video 0'), findsOneWidget);
      expect(find.text('Text post 1'), findsOneWidget);

      await pool.dispose();
    });
  });

  group('Event stream emits SwapEvent and ReconcileEvent', () {
    test('direct pool usage emits expected events', () async {
      final pool = createPool(
        config: const VideoPoolConfig(maxConcurrent: 3, preloadCount: 1),
      );

      final events = <PoolEvent>[];
      final subscription = pool.eventStream.listen(events.add);

      // Trigger reconciliation.
      pool.onVisibilityChanged(
        primaryIndex: 0,
        visibilityRatios: {0: 1.0},
      );
      await Future<void>.delayed(Duration.zero);

      // Verify ReconcileEvent was emitted.
      expect(
        events.whereType<ReconcileEvent>(),
        isNotEmpty,
        reason: 'ReconcileEvent should be emitted after onVisibilityChanged',
      );

      // Verify SwapEvent was emitted (pool assigns adapter to index 0).
      expect(
        events.whereType<SwapEvent>(),
        isNotEmpty,
        reason: 'SwapEvent should be emitted when pool assigns adapter',
      );

      // Verify the ReconcileEvent has correct primary index.
      final reconcileEvent = events.whereType<ReconcileEvent>().first;
      expect(reconcileEvent.primaryIndex, 0);
      expect(reconcileEvent.playCount, greaterThanOrEqualTo(1));

      // Verify the SwapEvent has correct toIndex.
      final swapEvent = events.whereType<SwapEvent>().first;
      expect(swapEvent.toIndex, isNonNegative);

      // Verify event timestamps are set.
      expect(reconcileEvent.timestamp, greaterThan(0));
      expect(swapEvent.timestamp, greaterThan(0));

      await subscription.cancel();
      await pool.dispose();
    });
  });

  group('DecoderBudget limits pool entry creation', () {
    test('pool creates only as many entries as budget allows', () async {
      final budget = GlobalDecoderBudget(totalTokens: 2);

      final pool = createPool(
        config: const VideoPoolConfig(maxConcurrent: 3),
        decoderBudget: budget,
      );

      // Pool requested 3 but budget only has 2 tokens.
      expect(createdAdapters.length, 2,
          reason: 'Only 2 entries should be created with budget of 2');
      expect(pool.statistics.totalCreated, 2);
      expect(pool.statistics.currentIdle, 2);

      await pool.dispose();
      budget.dispose();
    });
  });

  group('Multiple pools share decoder budget', () {
    test('pools compete for shared tokens and release on dispose', () async {
      final budget = GlobalDecoderBudget(totalTokens: 3);

      // Pool A: requests 2, gets 2.
      final poolA = createPool(
        config: const VideoPoolConfig(maxConcurrent: 2),
        decoderBudget: budget,
      );
      final poolAAdapterCount = createdAdapters.length;
      expect(poolAAdapterCount, 2,
          reason: 'Pool A should get 2 tokens');
      expect(poolA.statistics.totalCreated, 2);
      expect(poolA.statistics.currentIdle, 2);

      // Pool B: requests 2, but only 1 token remains.
      final poolB = createPool(
        config: const VideoPoolConfig(maxConcurrent: 2),
        decoderBudget: budget,
      );
      final poolBAdapterCount = createdAdapters.length - poolAAdapterCount;
      expect(poolBAdapterCount, 1,
          reason: 'Pool B should only get 1 token (1 remaining)');
      expect(poolB.statistics.totalCreated, 1);
      expect(poolB.statistics.currentIdle, 1);

      // Verify budget allocations total 3.
      expect(budget.allocations.values.fold<int>(0, (a, b) => a + b), 3,
          reason: 'All 3 tokens should be allocated');

      // Dispose pool A → releases 2 tokens.
      await poolA.dispose();

      // Now 2 tokens should be available again.
      // Pool C: requests 2, should get 2.
      final poolCAdapterStartIndex = createdAdapters.length;
      final poolC = createPool(
        config: const VideoPoolConfig(maxConcurrent: 2),
        decoderBudget: budget,
      );
      final poolCAdapterCount = createdAdapters.length - poolCAdapterStartIndex;
      expect(poolCAdapterCount, 2,
          reason: 'Pool C should get 2 tokens after Pool A released');
      expect(poolC.statistics.totalCreated, 2);
      expect(poolC.statistics.currentIdle, 2);

      await poolB.dispose();
      await poolC.dispose();
      budget.dispose();
    });
  });
}
