import 'package:flutter_test/flutter_test.dart';
import 'package:video_pool/video_pool.dart';

/// Tests for Phase 4: VideoSource resolutionHint and config validation.
void main() {
  group('VideoSource.resolutionHint', () {
    test('estimatedMemoryBytes returns null when no hint is set', () {
      const source = VideoSource(url: 'https://example.com/video.mp4');
      expect(source.estimatedMemoryBytes, isNull);
    });

    test('hd720 estimates ~11 MB', () {
      const source = VideoSource(
        url: 'https://example.com/video.mp4',
        resolutionHint: ResolutionHint.hd720,
      );
      // 1280 * 720 * 4 * 3 = 11,059,200
      expect(source.estimatedMemoryBytes, 1280 * 720 * 4 * 3);
    });

    test('hd1080 estimates ~24 MB', () {
      const source = VideoSource(
        url: 'https://example.com/video.mp4',
        resolutionHint: ResolutionHint.hd1080,
      );
      // 1920 * 1080 * 4 * 3 = 24,883,200
      expect(source.estimatedMemoryBytes, 1920 * 1080 * 4 * 3);
    });

    test('uhd4k estimates ~95 MB', () {
      const source = VideoSource(
        url: 'https://example.com/video.mp4',
        resolutionHint: ResolutionHint.uhd4k,
      );
      // 3840 * 2160 * 4 * 3 = 99,532,800
      expect(source.estimatedMemoryBytes, 3840 * 2160 * 4 * 3);
    });

    test('copyWith preserves resolutionHint', () {
      const source = VideoSource(
        url: 'https://example.com/video.mp4',
        resolutionHint: ResolutionHint.hd1080,
      );
      final copied = source.copyWith(url: 'https://example.com/v2.mp4');
      expect(copied.resolutionHint, ResolutionHint.hd1080);
    });

    test('copyWith overrides resolutionHint', () {
      const source = VideoSource(
        url: 'https://example.com/video.mp4',
        resolutionHint: ResolutionHint.hd720,
      );
      final copied = source.copyWith(resolutionHint: ResolutionHint.uhd4k);
      expect(copied.resolutionHint, ResolutionHint.uhd4k);
    });

    test('equality includes resolutionHint', () {
      const a = VideoSource(
        url: 'https://example.com/v.mp4',
        resolutionHint: ResolutionHint.hd720,
      );
      const b = VideoSource(
        url: 'https://example.com/v.mp4',
        resolutionHint: ResolutionHint.hd720,
      );
      const c = VideoSource(
        url: 'https://example.com/v.mp4',
        resolutionHint: ResolutionHint.hd1080,
      );

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('VideoPoolConfig validation', () {
    test('maxConcurrent <= 10 passes', () {
      const config = VideoPoolConfig(maxConcurrent: 10, preloadCount: 2);
      expect(config.maxConcurrent, 10);
    });

    test('preloadCount < maxConcurrent passes', () {
      const config = VideoPoolConfig(maxConcurrent: 5, preloadCount: 4);
      expect(config.preloadCount, 4);
    });
  });
}
