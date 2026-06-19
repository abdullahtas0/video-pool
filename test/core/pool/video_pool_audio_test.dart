import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:video_pool/video_pool.dart';

import '../../mocks/mock_player_adapter.dart';

/// Regression tests for the "no audio when scrolling back to a previously
/// loaded video" bug.
///
/// When an entry is demoted from primary to a preload/paused slot, the pool
/// mutes it (`setVolume(0)`). Volume was previously only ever restored inside
/// [PlayerAdapter.swapSource], which does NOT run on a cache hit. As a result,
/// scrolling back to an already-loaded video replayed it silently. The pool
/// must now restore full volume whenever an entry transitions to playing.
void main() {
  late List<MockPlayerAdapter> createdAdapters;
  late Map<int, VideoSource> sources;

  setUpAll(() {
    registerPlayerAdapterFallbacks();
  });

  setUp(() {
    createdAdapters = [];
    sources = {
      for (var i = 0; i < 6; i++)
        i: VideoSource(url: 'https://example.com/video$i.mp4'),
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

  VideoPool createPool() {
    return VideoPool(
      config: const VideoPoolConfig(maxConcurrent: 3, preloadCount: 1),
      adapterFactory: (id) => createMockAdapter(),
      sourceResolver: (index) => sources[index],
    );
  }

  test(
    'restores full volume when scrolling back to a previously played video',
    () async {
      final pool = createPool();

      // 1. Land on index 1 — it becomes primary and plays.
      pool.onVisibilityChanged(
        primaryIndex: 1,
        visibilityRatios: {0: 0.5, 1: 1.0, 2: 0.5},
      );
      await Future<void>.delayed(Duration.zero);

      // Capture the adapter bound to index 1. It keeps this index for the
      // remainder of the scenario (it's always within the preload window),
      // so it's the instance that should lose and then regain audio.
      final entry1 = pool.getEntryForIndex(1);
      expect(entry1, isNotNull);
      final adapter1 = entry1!.adapter as MockPlayerAdapter;

      // 2. Scroll forward to index 2. Index 1 is demoted to a preload slot
      //    and gets muted (setVolume(0)).
      pool.onVisibilityChanged(
        primaryIndex: 2,
        visibilityRatios: {1: 0.5, 2: 1.0, 3: 0.5},
      );
      await Future<void>.delayed(Duration.zero);

      // It must actually have been muted on demotion, otherwise this test
      // would pass vacuously.
      verify(() => adapter1.setVolume(0)).called(greaterThanOrEqualTo(1));

      // 3. Scroll back to index 1. It's a cache hit (no swapSource), so the
      //    pool itself must restore the volume before replaying.
      pool.onVisibilityChanged(
        primaryIndex: 1,
        visibilityRatios: {0: 0.5, 1: 1.0, 2: 0.5},
      );
      await Future<void>.delayed(Duration.zero);

      // The fix: full volume restored before the replay, and audio plays.
      verify(() => adapter1.setVolume(1.0)).called(greaterThanOrEqualTo(1));
      verify(() => adapter1.play()).called(greaterThanOrEqualTo(2));

      await pool.dispose();
    },
  );

  test(
    'togglePlayPause restores full volume before resuming',
    () async {
      final pool = createPool();

      pool.onVisibilityChanged(
        primaryIndex: 0,
        visibilityRatios: {0: 1.0},
      );
      await Future<void>.delayed(Duration.zero);

      final entry = pool.getEntryForIndex(0)!;
      final adapter = entry.adapter as MockPlayerAdapter;

      // Pause, then resume via the public toggle API.
      await pool.togglePlayPause(0); // playing -> paused
      await pool.togglePlayPause(0); // paused -> playing

      verify(() => adapter.setVolume(1.0)).called(greaterThanOrEqualTo(1));

      await pool.dispose();
    },
  );
}
