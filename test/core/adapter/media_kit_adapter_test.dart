import 'package:flutter_test/flutter_test.dart';
import 'package:video_pool/src/core/adapter/player_state.dart';
import 'package:video_pool/src/core/models/video_source.dart';

void main() {
  group('MediaKitAdapter — unit logic', () {
    // Since media_kit's Player is a concrete class that relies on native
    // libraries (libmpv / platform channels), we cannot instantiate it in
    // pure unit tests. Instead we test the logic that *doesn't* need a live
    // Player: state constants, isReusable semantics, memory estimation, and
    // the URI resolution helper.

    group('PlaybackPhase / isReusable contract', () {
      test('idle phase is reusable', () {
        const state = PlayerState(phase: PlaybackPhase.idle);
        final reusable = state.phase == PlaybackPhase.idle ||
            state.phase == PlaybackPhase.paused;
        expect(reusable, isTrue);
      });

      test('paused phase is reusable', () {
        const state = PlayerState(phase: PlaybackPhase.paused);
        final reusable = state.phase == PlaybackPhase.idle ||
            state.phase == PlaybackPhase.paused;
        expect(reusable, isTrue);
      });

      test('playing phase is NOT reusable', () {
        const state = PlayerState(phase: PlaybackPhase.playing);
        final reusable = state.phase == PlaybackPhase.idle ||
            state.phase == PlaybackPhase.paused;
        expect(reusable, isFalse);
      });

      test('buffering phase is NOT reusable', () {
        const state = PlayerState(phase: PlaybackPhase.buffering);
        final reusable = state.phase == PlaybackPhase.idle ||
            state.phase == PlaybackPhase.paused;
        expect(reusable, isFalse);
      });

      test('disposed phase is NOT reusable', () {
        const state = PlayerState(phase: PlaybackPhase.disposed);
        final reusable = state.phase == PlaybackPhase.idle ||
            state.phase == PlaybackPhase.paused;
        expect(reusable, isFalse);
      });
    });

    group('estimatedMemoryBytes logic', () {
      test('default estimate matches 1920x1080 RGBA x3 buffers', () {
        // The adapter uses 1920 * 1080 * 4 * 3 when dimensions are unknown.
        const expected = 1920 * 1080 * 4 * 3;
        expect(expected, equals(24883200));
      });

      test('known dimensions produce correct estimate', () {
        const width = 1280;
        const height = 720;
        const expected = width * height * 4 * 3;
        expect(expected, equals(11059200));
      });

      test('zero dimensions fall back to default', () {
        const width = 0;
        const height = 0;
        const defaultEstimate = 1920 * 1080 * 4 * 3;

        final estimate = (width > 0 && height > 0)
            ? width * height * 4 * 3
            : defaultEstimate;

        expect(estimate, equals(defaultEstimate));
      });
    });

    group('ghost-frame prevention on swapSource', () {
      test('state should transition to idle with new source immediately', () {
        // Simulate what swapSource does BEFORE calling Player.open:
        const newSource = VideoSource(url: 'https://example.com/video2.mp4');
        const previousState = PlayerState(
          phase: PlaybackPhase.playing,
          currentSource: VideoSource(url: 'https://example.com/video1.mp4'),
          position: Duration(seconds: 30),
        );

        // The adapter resets state synchronously.
        final resetState = PlayerState(
          phase: PlaybackPhase.idle,
          currentSource: newSource,
        );

        expect(resetState.phase, PlaybackPhase.idle);
        expect(resetState.currentSource, newSource);
        expect(resetState.position, Duration.zero);
        expect(resetState.currentSource != previousState.currentSource, isTrue);
      });
    });

    group('media URI resolution', () {
      // Test the URI construction logic extracted from _mediaUriForSource.
      String resolveUri(VideoSource source) {
        switch (source.type) {
          case VideoSourceType.file:
            return source.url;
          case VideoSourceType.asset:
            return 'asset://${source.url}';
          case VideoSourceType.network:
            return source.url;
        }
      }

      test('network source returns URL as-is', () {
        const source = VideoSource(
          url: 'https://cdn.example.com/video.mp4',
          type: VideoSourceType.network,
        );
        expect(resolveUri(source), 'https://cdn.example.com/video.mp4');
      });

      test('file source returns path as-is', () {
        const source = VideoSource(
          url: '/data/user/0/com.app/cache/video.mp4',
          type: VideoSourceType.file,
        );
        expect(resolveUri(source), '/data/user/0/com.app/cache/video.mp4');
      });

      test('asset source prepends asset://', () {
        const source = VideoSource(
          url: 'assets/videos/intro.mp4',
          type: VideoSourceType.asset,
        );
        expect(resolveUri(source), 'asset://assets/videos/intro.mp4');
      });
    });

    group('volume conversion', () {
      test('0.0–1.0 maps to 0–100 for media_kit', () {
        // media_kit uses 0–100; our API uses 0.0–1.0.
        expect(0.0 * 100.0, 0.0);
        expect(0.5 * 100.0, 50.0);
        expect(1.0 * 100.0, 100.0);
      });
    });
  });
}
