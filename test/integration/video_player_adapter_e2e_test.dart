import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:video_pool/video_pool.dart';

import '../core/adapter/fake_video_player_platform.dart';

/// Polls [condition] until true or [maxIterations] is reached.
Future<void> _waitUntil(
  bool Function() condition, {
  Duration step = const Duration(milliseconds: 10),
  int maxIterations = 300,
}) async {
  for (var i = 0; i < maxIterations; i++) {
    if (condition()) return;
    await Future<void>.delayed(step);
  }
}

void main() {
  // VideoPlayerController.initialize() registers a WidgetsBinding lifecycle
  // observer, so a binding must exist even for these non-widget tests.
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeVideoPlayerPlatform fake;

  setUp(() {
    fake = FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = fake;
  });

  const sources = [
    VideoSource(url: 'https://example.com/0.mp4'),
    VideoSource(url: 'https://example.com/1.mp4'),
    VideoSource(url: 'https://example.com/2.mp4'),
  ];

  test('VideoPool drives a real VideoPlayerAdapter end-to-end via the platform',
      () async {
    final events = <PoolEvent>[];
    final pool = VideoPool(
      config: const VideoPoolConfig(maxConcurrent: 2, preloadCount: 0),
      adapterFactory: (_) => VideoPlayerAdapter(),
      sourceResolver: (index) =>
          index >= 0 && index < sources.length ? sources[index] : null,
    );
    final subscription = pool.eventStream.listen(events.add);

    // Two adapters (each a real VideoPlayerAdapter) are created up front.
    expect(pool.statistics.totalCreated, 2);

    // Become visible at index 0 — the pool reconciles, swaps the source onto an
    // adapter, initializes the underlying VideoPlayerController, and plays it.
    pool.onVisibilityChanged(primaryIndex: 0, visibilityRatios: {0: 1.0});

    // The whole chain (reconcile → swapSource → controller.initialize via the
    // fake event stream → play) is genuinely async; wait for it to settle.
    await _waitUntil(() => fake.calls.contains('play'));

    // End-to-end proof: the pool drove a real VideoPlayerAdapter, which created
    // a real VideoPlayerController, which talked to the platform.
    expect(fake.calls, contains('create'),
        reason: 'adapter should create a controller through the platform');
    expect(fake.calls, contains('play'),
        reason: 'pool should play the primary entry through the adapter');
    expect(pool.getEntryForIndex(0), isNotNull);
    expect(pool.statistics.currentActive, greaterThanOrEqualTo(1));
    expect(events.whereType<SwapEvent>(), isNotEmpty);

    await subscription.cancel();
    await pool.dispose();
  });

  test('scrolling reassigns and plays the new primary via the adapter',
      () async {
    final pool = VideoPool(
      config: const VideoPoolConfig(maxConcurrent: 2, preloadCount: 0),
      adapterFactory: (_) => VideoPlayerAdapter(),
      sourceResolver: (index) =>
          index >= 0 && index < sources.length ? sources[index] : null,
    );

    pool.onVisibilityChanged(primaryIndex: 0, visibilityRatios: {0: 1.0});
    await _waitUntil(() => pool.getEntryForIndex(0) != null);

    final createsAfterFirst = fake.calls.where((c) => c == 'create').length;

    // Scroll to index 2.
    pool.onVisibilityChanged(primaryIndex: 2, visibilityRatios: {2: 1.0});
    await _waitUntil(() => pool.getEntryForIndex(2) != null);

    expect(pool.getEntryForIndex(2), isNotNull);
    // A fresh controller is created for the new source (recreate semantics).
    expect(
      fake.calls.where((c) => c == 'create').length,
      greaterThan(createsAfterFirst),
    );

    await pool.dispose();
  });
}
