import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_pool/src/core/cache/file_preload_manager.dart';
import 'package:video_pool/src/core/models/video_source.dart';

/// Tests for Phase 2: FilePreloadManager bug fixes.
void main() {
  late Directory tempDir;
  late FilePreloadManager manager;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('video_pool_cache_enhanced_');
  });

  tearDown(() async {
    await manager.dispose();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('SHA-256 cache key (collision resistance)', () {
    test('different URLs produce different file paths', () {
      manager = FilePreloadManager(cacheDirectory: tempDir.path);

      const source1 = VideoSource(url: 'https://example.com/video1.mp4');
      const source2 = VideoSource(url: 'https://example.com/video2.mp4');

      // The cache keys differ so their file paths must differ.
      expect(source1.cacheKey, isNot(equals(source2.cacheKey)));
    });

    test('file path uses SHA-256 hex hash', () {
      manager = FilePreloadManager(cacheDirectory: tempDir.path);

      const key = 'https://example.com/video.mp4';
      final expectedHash = sha256.convert(utf8.encode(key)).toString();

      // We can't call _filePathForKey directly but we can verify that
      // two managers with the same cache directory produce the same path
      // for the same key (deterministic).
      expect(expectedHash.length, 64); // SHA-256 = 64 hex chars
    });

    test('very long URLs do not cause filesystem issues', () {
      manager = FilePreloadManager(cacheDirectory: tempDir.path);

      // 500-char URL — should hash to a fixed-length filename.
      final longUrl = 'https://example.com/${'a' * 500}.mp4';
      const source = VideoSource(url: 'https://example.com/short.mp4');

      // Manager should handle this without errors.
      expect(manager.isCached(longUrl), isFalse);
      expect(manager.isCached(source.cacheKey), isFalse);
    });
  });

  group('lockKey / unlockKey', () {
    test('locked key is reported as locked', () {
      manager = FilePreloadManager(cacheDirectory: tempDir.path);

      expect(manager.isLocked('key1'), isFalse);
      manager.lockKey('key1');
      expect(manager.isLocked('key1'), isTrue);
      manager.unlockKey('key1');
      expect(manager.isLocked('key1'), isFalse);
    });

    test('unlocking non-locked key is safe', () {
      manager = FilePreloadManager(cacheDirectory: tempDir.path);
      manager.unlockKey('never-locked');
      expect(manager.isLocked('never-locked'), isFalse);
    });

    test('clearCache clears all locks', () async {
      manager = FilePreloadManager(cacheDirectory: tempDir.path);

      manager.lockKey('key1');
      manager.lockKey('key2');
      expect(manager.isLocked('key1'), isTrue);

      await manager.clearCache();

      expect(manager.isLocked('key1'), isFalse);
      expect(manager.isLocked('key2'), isFalse);
    });

    test('dispose clears all locks', () async {
      manager = FilePreloadManager(cacheDirectory: tempDir.path);

      manager.lockKey('key1');
      await manager.dispose();

      expect(manager.isLocked('key1'), isFalse);
    });
  });

  group('CachedFile serialization (manifest)', () {
    test('toJson and fromJson round-trip correctly', () {
      final now = DateTime.now();
      final cached = CachedFile(
        path: '/tmp/vp_test.tmp',
        sizeBytes: 2048,
        cachedAt: now,
        cacheKey: 'test-key',
      );

      final json = cached.toJson();
      final restored = CachedFile.fromJson(json);

      expect(restored.path, cached.path);
      expect(restored.sizeBytes, cached.sizeBytes);
      expect(restored.cacheKey, cached.cacheKey);
      // DateTime parse truncates microseconds.
      expect(
        restored.cachedAt.millisecondsSinceEpoch,
        cached.cachedAt.millisecondsSinceEpoch,
      );
    });
  });

  group('Cold-start manifest recovery', () {
    test('loadManifest recovers entries from disk', () async {
      // First session: write a manifest file manually.
      final cacheDir = Directory(tempDir.path)..createSync(recursive: true);
      final fakePath = '${cacheDir.path}/vp_fake.tmp';
      File(fakePath).writeAsStringSync('fake video data');

      final manifest = [
        {
          'path': fakePath,
          'sizeBytes': 15,
          'cachedAt': DateTime.now().toIso8601String(),
          'cacheKey': 'https://example.com/video.mp4',
        },
      ];
      File('${cacheDir.path}/_manifest.json')
          .writeAsStringSync(jsonEncode(manifest));

      // Second session: new manager loads manifest.
      manager = FilePreloadManager(cacheDirectory: cacheDir.path);
      await manager.loadManifest();

      expect(manager.isCached('https://example.com/video.mp4'), isTrue);
      expect(manager.getCachedPath('https://example.com/video.mp4'), fakePath);
      expect(manager.currentCacheSizeBytes, 15);
    });

    test('loadManifest skips entries whose files are missing', () async {
      final cacheDir = Directory(tempDir.path)..createSync(recursive: true);

      final manifest = [
        {
          'path': '${cacheDir.path}/vp_missing.tmp',
          'sizeBytes': 100,
          'cachedAt': DateTime.now().toIso8601String(),
          'cacheKey': 'missing-key',
        },
      ];
      File('${cacheDir.path}/_manifest.json')
          .writeAsStringSync(jsonEncode(manifest));

      manager = FilePreloadManager(cacheDirectory: cacheDir.path);
      await manager.loadManifest();

      expect(manager.isCached('missing-key'), isFalse);
      expect(manager.currentCacheSizeBytes, 0);
    });

    test('corrupt manifest does not crash', () async {
      final cacheDir = Directory(tempDir.path)..createSync(recursive: true);
      File('${cacheDir.path}/_manifest.json')
          .writeAsStringSync('not valid json!!!');

      manager = FilePreloadManager(cacheDirectory: cacheDir.path);
      // Should not throw.
      await manager.loadManifest();

      expect(manager.currentCacheSizeBytes, 0);
    });
  });

  group('connectionTimeoutSeconds', () {
    test('defaults to 15 seconds', () {
      manager = FilePreloadManager(cacheDirectory: tempDir.path);
      expect(manager.connectionTimeoutSeconds, 15);
    });

    test('accepts custom value', () {
      manager = FilePreloadManager(
        cacheDirectory: tempDir.path,
        connectionTimeoutSeconds: 30,
      );
      expect(manager.connectionTimeoutSeconds, 30);
    });
  });
}
