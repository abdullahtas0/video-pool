@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:video_pool/src/core/adapter/network_tuning_web.dart'
    as web_tuning;
import 'package:video_pool/src/core/cache/file_preload_manager_web.dart';
import 'package:video_pool/src/core/cache/thumbnail_extractor_web.dart';
import 'package:video_pool/src/core/models/video_source.dart';

class _MockPlayer extends Mock implements Player {}

void main() {
  group('FilePreloadManager (web stub)', () {
    late FilePreloadManager manager;

    setUp(() {
      manager = FilePreloadManager(cacheDirectory: '/unused/on/web');
    });

    tearDown(() async => manager.dispose());

    test('stores constructor configuration', () {
      final m = FilePreloadManager(
        cacheDirectory: '/c',
        maxCacheSizeBytes: 1234,
        connectionTimeoutSeconds: 7,
      );
      expect(m.cacheDirectory, '/c');
      expect(m.maxCacheSizeBytes, 1234);
      expect(m.connectionTimeoutSeconds, 7);
    });

    test('reports an empty cache', () {
      expect(manager.currentCacheSizeBytes, 0);
      expect(manager.isCached('k'), isFalse);
      expect(manager.getCachedPath('k'), isNull);
      expect(manager.getThumbnailPath('k'), isNull);
    });

    test('prefetch resolves to null (caller falls back to network)', () async {
      final result = await manager.prefetch(
        const VideoSource(url: 'https://example.com/v.m3u8'),
      );
      expect(result, isNull);
    });

    test('lock/unlock/isLocked stay consistent', () {
      expect(manager.isLocked('k'), isFalse);
      manager.lockKey('k');
      expect(manager.isLocked('k'), isTrue);
      manager.unlockKey('k');
      expect(manager.isLocked('k'), isFalse);
    });

    test('lifecycle methods complete without throwing', () async {
      await expectLater(manager.loadManifest(), completes);
      await expectLater(manager.cleanupIncomplete(), completes);
      manager.cancelPrefetch('k');
      await expectLater(manager.clearCache(), completes);
    });
  });

  group('ThumbnailExtractor (web stub)', () {
    test('isFastStart is always false', () async {
      expect(await ThumbnailExtractor.isFastStart('/any/path.mp4'), isFalse);
    });

    test('extract resolves to null', () async {
      final extractor = ThumbnailExtractor();
      final result = await extractor.extract(
        videoPath: '/v.mp4',
        outputPath: '/t.jpg',
      );
      expect(result, isNull);
      extractor.dispose();
    });

    test('extract returns null after dispose', () async {
      final extractor = ThumbnailExtractor()..dispose();
      expect(
        await extractor.extract(videoPath: '/v.mp4', outputPath: '/t.jpg'),
        isNull,
      );
    });
  });

  group('applyNetworkTuning (web stub)', () {
    test('is a no-op that never touches the player', () async {
      final player = _MockPlayer();
      await web_tuning.applyNetworkTuning(player);
      verifyZeroInteractions(player);
    });
  });
}
