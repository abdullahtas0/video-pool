import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_pool/src/core/cache/file_preload_manager.dart';

void main() {
  group('CachedFile serialization', () {
    test('fromJson handles missing new fields with defaults', () {
      // Simulate an old manifest entry without complete, etag, targetBytes,
      // lastCheckedAt fields.
      final oldJson = {
        'path': '/tmp/video.tmp',
        'sizeBytes': 2048,
        'cachedAt': '2025-01-15T10:30:00.000Z',
        'cacheKey': 'old-key',
      };

      final cached = CachedFile.fromJson(oldJson);

      expect(cached.path, '/tmp/video.tmp');
      expect(cached.sizeBytes, 2048);
      expect(cached.cacheKey, 'old-key');
      // Defaults for missing fields:
      expect(cached.complete, isTrue);
      expect(cached.etag, isNull);
      expect(cached.targetBytes, 2048); // defaults to sizeBytes
      expect(cached.lastCheckedAt, isNull);
    });

    test('toJson includes complete, etag, targetBytes fields', () {
      final now = DateTime.parse('2025-06-01T12:00:00.000Z');
      final cached = CachedFile(
        path: '/tmp/video.tmp',
        sizeBytes: 1024,
        cachedAt: now,
        cacheKey: 'test-key',
        complete: false,
        etag: '"abc123"',
        targetBytes: 2097152,
        lastCheckedAt: now,
      );

      final jsonMap = cached.toJson();

      expect(jsonMap['path'], '/tmp/video.tmp');
      expect(jsonMap['sizeBytes'], 1024);
      expect(jsonMap['cacheKey'], 'test-key');
      expect(jsonMap['complete'], isFalse);
      expect(jsonMap['etag'], '"abc123"');
      expect(jsonMap['targetBytes'], 2097152);
      expect(jsonMap['lastCheckedAt'], '2025-06-01T12:00:00.000Z');
    });

    test('round-trip serialization preserves all fields', () {
      final now = DateTime.parse('2025-06-01T12:00:00.000Z');
      final original = CachedFile(
        path: '/tmp/video.tmp',
        sizeBytes: 512,
        cachedAt: now,
        cacheKey: 'round-trip',
        complete: false,
        etag: '"etag-value"',
        targetBytes: 4096,
        lastCheckedAt: now,
      );

      final restored = CachedFile.fromJson(original.toJson());

      expect(restored.path, original.path);
      expect(restored.sizeBytes, original.sizeBytes);
      expect(restored.cachedAt, original.cachedAt);
      expect(restored.cacheKey, original.cacheKey);
      expect(restored.complete, original.complete);
      expect(restored.etag, original.etag);
      expect(restored.targetBytes, original.targetBytes);
      expect(restored.lastCheckedAt, original.lastCheckedAt);
    });

    test('constructor defaults complete to true and targetBytes to sizeBytes',
        () {
      final cached = CachedFile(
        path: '/tmp/video.tmp',
        sizeBytes: 2048,
        cachedAt: DateTime.now(),
        cacheKey: 'default-test',
      );

      expect(cached.complete, isTrue);
      expect(cached.targetBytes, 2048);
      expect(cached.etag, isNull);
      expect(cached.lastCheckedAt, isNull);
    });
  });

  group('FilePreloadManager resume features', () {
    late Directory tempDir;
    late FilePreloadManager manager;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('video_pool_resume_test_');
    });

    tearDown(() async {
      await manager.dispose();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    group('getCachedPath filtering', () {
      test('returns null for incomplete entries', () async {
        manager = FilePreloadManager(cacheDirectory: tempDir.path);

        // Write a manifest with an incomplete entry.
        final incompleteCached = CachedFile(
          path: '${tempDir.path}/partial.tmp',
          sizeBytes: 512,
          cachedAt: DateTime.now(),
          cacheKey: 'partial-key',
          complete: false,
          etag: '"some-etag"',
          targetBytes: 2097152,
        );

        // Create the file on disk so loadManifest doesn't skip it.
        await File(incompleteCached.path).writeAsBytes(List.filled(512, 0));

        final manifestFile = File('${tempDir.path}/_manifest.json');
        await manifestFile.writeAsString(
          json.encode([incompleteCached.toJson()]),
        );

        await manager.loadManifest();

        // getCachedPath should return null for incomplete entries.
        expect(manager.getCachedPath('partial-key'), isNull);
        // But isCached should still return true (it's in the cache).
        expect(manager.isCached('partial-key'), isTrue);
      });

      test('returns path for complete entries', () async {
        manager = FilePreloadManager(cacheDirectory: tempDir.path);

        final completeCached = CachedFile(
          path: '${tempDir.path}/complete.tmp',
          sizeBytes: 2048,
          cachedAt: DateTime.now(),
          cacheKey: 'complete-key',
          complete: true,
        );

        await File(completeCached.path).writeAsBytes(List.filled(2048, 0));

        final manifestFile = File('${tempDir.path}/_manifest.json');
        await manifestFile.writeAsString(
          json.encode([completeCached.toJson()]),
        );

        await manager.loadManifest();

        expect(manager.getCachedPath('complete-key'), completeCached.path);
      });
    });

    group('cleanupIncomplete', () {
      test('removes entries older than maxAge', () async {
        manager = FilePreloadManager(cacheDirectory: tempDir.path);

        // Create an incomplete entry that is 48 hours old.
        final oldTime = DateTime.now().subtract(const Duration(hours: 48));
        final oldIncomplete = CachedFile(
          path: '${tempDir.path}/old_partial.tmp',
          sizeBytes: 256,
          cachedAt: oldTime,
          cacheKey: 'old-partial',
          complete: false,
          lastCheckedAt: oldTime,
          targetBytes: 2097152,
        );

        await File(oldIncomplete.path).writeAsBytes(List.filled(256, 0));

        final manifestFile = File('${tempDir.path}/_manifest.json');
        await manifestFile.writeAsString(
          json.encode([oldIncomplete.toJson()]),
        );

        await manager.loadManifest();

        // After loadManifest (which calls cleanupIncomplete), the old
        // incomplete entry should be removed.
        expect(manager.isCached('old-partial'), isFalse);
        expect(manager.getCachedPath('old-partial'), isNull);
        // File should be deleted from disk.
        expect(await File(oldIncomplete.path).exists(), isFalse);
      });

      test('preserves recent incomplete entries', () async {
        manager = FilePreloadManager(cacheDirectory: tempDir.path);

        // Create an incomplete entry that is only 1 hour old.
        final recentTime = DateTime.now().subtract(const Duration(hours: 1));
        final recentIncomplete = CachedFile(
          path: '${tempDir.path}/recent_partial.tmp',
          sizeBytes: 512,
          cachedAt: recentTime,
          cacheKey: 'recent-partial',
          complete: false,
          lastCheckedAt: recentTime,
          targetBytes: 2097152,
        );

        await File(recentIncomplete.path).writeAsBytes(List.filled(512, 0));

        final manifestFile = File('${tempDir.path}/_manifest.json');
        await manifestFile.writeAsString(
          json.encode([recentIncomplete.toJson()]),
        );

        await manager.loadManifest();

        // Recent incomplete entry should still be in cache.
        expect(manager.isCached('recent-partial'), isTrue);
        // But getCachedPath should still return null (incomplete).
        expect(manager.getCachedPath('recent-partial'), isNull);
        // File should still exist on disk.
        expect(await File(recentIncomplete.path).exists(), isTrue);
      });

      test('preserves complete entries regardless of age', () async {
        manager = FilePreloadManager(cacheDirectory: tempDir.path);

        final oldTime = DateTime.now().subtract(const Duration(hours: 48));
        final oldComplete = CachedFile(
          path: '${tempDir.path}/old_complete.tmp',
          sizeBytes: 1024,
          cachedAt: oldTime,
          cacheKey: 'old-complete',
          complete: true,
        );

        await File(oldComplete.path).writeAsBytes(List.filled(1024, 0));

        final manifestFile = File('${tempDir.path}/_manifest.json');
        await manifestFile.writeAsString(
          json.encode([oldComplete.toJson()]),
        );

        await manager.loadManifest();

        // Complete entries are never cleaned up by the janitor.
        expect(manager.isCached('old-complete'), isTrue);
        expect(manager.getCachedPath('old-complete'), oldComplete.path);
      });

      test('uses cachedAt when lastCheckedAt is null', () async {
        manager = FilePreloadManager(cacheDirectory: tempDir.path);

        final oldTime = DateTime.now().subtract(const Duration(hours: 48));
        final noLastChecked = CachedFile(
          path: '${tempDir.path}/no_lastchecked.tmp',
          sizeBytes: 128,
          cachedAt: oldTime,
          cacheKey: 'no-lastchecked',
          complete: false,
          lastCheckedAt: null,
          targetBytes: 2097152,
        );

        await File(noLastChecked.path).writeAsBytes(List.filled(128, 0));

        final manifestFile = File('${tempDir.path}/_manifest.json');
        await manifestFile.writeAsString(
          json.encode([noLastChecked.toJson()]),
        );

        await manager.loadManifest();

        // Should be cleaned up because cachedAt is older than 24h.
        expect(manager.isCached('no-lastchecked'), isFalse);
      });

      test('custom maxAge is respected', () async {
        manager = FilePreloadManager(cacheDirectory: tempDir.path);

        // Create an incomplete entry that is 2 hours old.
        final twoHoursAgo = DateTime.now().subtract(const Duration(hours: 2));
        final entry = CachedFile(
          path: '${tempDir.path}/custom_age.tmp',
          sizeBytes: 256,
          cachedAt: twoHoursAgo,
          cacheKey: 'custom-age',
          complete: false,
          lastCheckedAt: twoHoursAgo,
          targetBytes: 2097152,
        );

        await File(entry.path).writeAsBytes(List.filled(256, 0));

        final manifestFile = File('${tempDir.path}/_manifest.json');
        await manifestFile.writeAsString(json.encode([entry.toJson()]));

        // Load without cleanup (loadManifest uses default 24h).
        await manager.loadManifest();
        // Entry should still exist (only 2h old, default is 24h).
        expect(manager.isCached('custom-age'), isTrue);

        // Now run cleanup with a 1-hour maxAge.
        await manager.cleanupIncomplete(
          maxAge: const Duration(hours: 1),
        );

        // Now it should be removed.
        expect(manager.isCached('custom-age'), isFalse);
      });
    });
  });
}
