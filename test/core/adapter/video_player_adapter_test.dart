import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:video_pool/src/core/adapter/player_state.dart';
import 'package:video_pool/src/core/adapter/video_player_adapter.dart';
import 'package:video_pool/src/core/models/video_source.dart';

import 'fake_video_player_platform.dart';

void main() {
  late FakeVideoPlayerPlatform fake;

  setUp(() {
    fake = FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = fake;
  });

  const source = VideoSource(url: 'https://example.com/v.mp4');

  group('VideoPlayerAdapter swapSource', () {
    test('initializes a controller and reports a reusable (paused) state',
        () async {
      final adapter = VideoPlayerAdapter();
      await adapter.swapSource(source);

      expect(adapter.stateNotifier.value.phase, PlaybackPhase.paused);
      expect(adapter.stateNotifier.value.currentSource, source);
      expect(adapter.isReusable, isTrue);
      expect(adapter.duration, const Duration(seconds: 10));
      expect(fake.calls, contains('create'));

      await adapter.dispose();
    });

    test('disposes the previous controller (recreate semantics)', () async {
      final adapter = VideoPlayerAdapter();
      await adapter.swapSource(const VideoSource(url: 'https://a.com/a.mp4'));
      await adapter.swapSource(const VideoSource(url: 'https://b.com/b.mp4'));

      expect(fake.calls.where((c) => c == 'create').length, 2);
      expect(fake.calls, contains('dispose'));

      await adapter.dispose();
    });

    test('reports error phase when controller creation fails', () async {
      fake.failCreate = true;
      final adapter = VideoPlayerAdapter();
      await adapter.swapSource(source);

      expect(adapter.stateNotifier.value.phase, PlaybackPhase.error);
      expect(adapter.stateNotifier.value.errorMessage, isNotNull);

      await adapter.dispose();
    });

    test('reports error phase when the factory throws', () async {
      final adapter = VideoPlayerAdapter(
        controllerFactory: (_) => throw StateError('boom'),
      );
      await adapter.swapSource(source);

      expect(adapter.stateNotifier.value.phase, PlaybackPhase.error);
      expect(adapter.stateNotifier.value.errorMessage, contains('boom'));

      await adapter.dispose();
    });
  });

  group('VideoPlayerAdapter playback controls', () {
    test('play -> playing phase, not reusable', () async {
      final adapter = VideoPlayerAdapter();
      await adapter.swapSource(source);
      await adapter.play();

      expect(adapter.stateNotifier.value.phase, PlaybackPhase.playing);
      expect(adapter.isReusable, isFalse);
      expect(fake.calls, contains('play'));

      await adapter.dispose();
    });

    test('pause after play -> paused phase', () async {
      final adapter = VideoPlayerAdapter();
      await adapter.swapSource(source);
      await adapter.play();
      await adapter.pause();

      expect(adapter.stateNotifier.value.phase, PlaybackPhase.paused);
      expect(adapter.isReusable, isTrue);

      await adapter.dispose();
    });

    test('setVolume clamps to 0..1 and delegates', () async {
      final adapter = VideoPlayerAdapter();
      await adapter.swapSource(source);
      await adapter.setVolume(2.0);

      expect(fake.calls, contains('setVolume:1.0'));

      await adapter.dispose();
    });

    test('seekTo / setSpeed / setLooping delegate to the controller', () async {
      final adapter = VideoPlayerAdapter();
      await adapter.swapSource(source);
      // video_player only forwards playback speed to the platform while
      // playing, so start playback before asserting setSpeed.
      await adapter.play();
      await adapter.seekTo(const Duration(seconds: 3));
      await adapter.setSpeed(1.5);
      await adapter.setLooping(true);

      expect(fake.calls, contains('seekTo:3000'));
      expect(fake.calls, contains('setSpeed:1.5'));
      expect(fake.calls, contains('setLooping:true'));

      await adapter.dispose();
    });
  });

  group('VideoPlayerAdapter misc', () {
    test('estimatedMemoryBytes derives from the video size', () async {
      fake.initializedSize = const Size(1920, 1080);
      final adapter = VideoPlayerAdapter();
      await adapter.swapSource(source);

      expect(adapter.estimatedMemoryBytes, 1920 * 1080 * 4 * 3);

      await adapter.dispose();
    });

    test('dispose marks the adapter disposed and tears down the controller',
        () async {
      final adapter = VideoPlayerAdapter();
      await adapter.swapSource(source);
      await adapter.dispose();

      expect(adapter.stateNotifier.value.phase, PlaybackPhase.disposed);
      expect(fake.calls, contains('dispose'));
    });

    testWidgets(
        'videoWidget is a stable instance and renders nothing '
        'before a source is loaded', (tester) async {
      final adapter = VideoPlayerAdapter();

      // The host widget must be the same instance across reads so the element
      // (and its texture host) stays mounted across source swaps.
      expect(identical(adapter.videoWidget, adapter.videoWidget), isTrue);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: adapter.videoWidget,
        ),
      );

      expect(find.byType(VideoPlayer), findsNothing);

      await adapter.dispose();
    });

    testWidgets('videoWidget renders a VideoPlayer once initialized',
        (tester) async {
      final adapter = VideoPlayerAdapter();

      // Use runAsync so the real Stream/initialize completes (the fake emits
      // its initialized event outside fake-async time).
      await tester.runAsync(() => adapter.swapSource(source));

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: adapter.videoWidget,
        ),
      );
      await tester.pump();

      expect(find.byType(VideoPlayer), findsOneWidget);

      await tester.runAsync(() => adapter.dispose());
    });
  });
}
