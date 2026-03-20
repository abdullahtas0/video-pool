import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

import '../memory/lru_cache.dart';
import '../models/video_source.dart';

/// Metadata for a cached video file on disk.
class CachedFile {
  /// Creates a new [CachedFile].
  const CachedFile({
    required this.path,
    required this.sizeBytes,
    required this.cachedAt,
    required this.cacheKey,
  });

  /// Creates a [CachedFile] from a JSON map (for manifest deserialization).
  factory CachedFile.fromJson(Map<String, dynamic> json) {
    return CachedFile(
      path: json['path'] as String,
      sizeBytes: json['sizeBytes'] as int,
      cachedAt: DateTime.parse(json['cachedAt'] as String),
      cacheKey: json['cacheKey'] as String,
    );
  }

  /// Absolute path to the cached file on disk.
  final String path;

  /// Size of the cached file in bytes.
  final int sizeBytes;

  /// When this file was cached.
  final DateTime cachedAt;

  /// The cache key associated with this entry.
  final String cacheKey;

  /// Converts this to a JSON map (for manifest serialization).
  Map<String, dynamic> toJson() => {
        'path': path,
        'sizeBytes': sizeBytes,
        'cachedAt': cachedAt.toIso8601String(),
        'cacheKey': cacheKey,
      };
}

/// Parameters passed to the download isolate.
class _DownloadParams {
  const _DownloadParams({
    required this.url,
    required this.destPath,
    required this.headers,
    required this.bytesToFetch,
    required this.connectionTimeoutSeconds,
  });

  final String url;
  final String destPath;
  final Map<String, String> headers;
  final int bytesToFetch;
  final int connectionTimeoutSeconds;
}

/// Result returned from the download isolate.
class _DownloadResult {
  const _DownloadResult({
    required this.path,
    required this.sizeBytes,
    this.error,
  });

  final String path;
  final int sizeBytes;
  final String? error;
}

/// Manages pre-fetching video data to disk so that the player can open
/// local files instead of streaming from the network.
///
/// Downloads run in a separate isolate to avoid blocking the UI thread.
/// An [LruCache] tracks entries and evicts the oldest when the cache
/// exceeds [maxCacheSizeBytes].
///
/// Usage:
/// ```dart
/// final manager = FilePreloadManager(cacheDirectory: '/tmp/video_cache');
/// final localPath = await manager.prefetch(source);
/// if (localPath != null) {
///   // Open localPath with the player for instant playback.
/// }
/// ```
class FilePreloadManager {
  /// Creates a [FilePreloadManager].
  ///
  /// [cacheDirectory] must be a writable directory path.
  /// [maxCacheSizeBytes] defaults to 500 MB.
  /// [maxEntries] defaults to 100 entries in the LRU index.
  /// [connectionTimeoutSeconds] defaults to 15 seconds.
  FilePreloadManager({
    required this.cacheDirectory,
    this.maxCacheSizeBytes = 500 * 1024 * 1024,
    int maxEntries = 100,
    this.connectionTimeoutSeconds = 15,
  }) : _diskCache = LruCache<String, CachedFile>(
          maxSize: maxEntries,
        );

  /// The directory where cached video files are stored.
  final String cacheDirectory;

  /// Maximum total size of all cached files in bytes. Default: 500 MB.
  final int maxCacheSizeBytes;

  /// HTTP connection timeout in seconds.
  final int connectionTimeoutSeconds;

  /// In-memory LRU index of cached files.
  final LruCache<String, CachedFile> _diskCache;

  /// Ongoing prefetch operations keyed by cache key.
  final Map<String, Completer<String?>> _activeFetches = {};

  /// Keys that are currently in use by a player and must not be evicted.
  final Set<String> _lockedKeys = {};

  /// Track total size of cached data on disk.
  int _currentCacheSizeBytes = 0;

  bool _disposed = false;

  /// Current total size of cached files on disk.
  int get currentCacheSizeBytes => _currentCacheSizeBytes;

  /// Whether the given [cacheKey] has a completed cache entry.
  bool isCached(String cacheKey) => _diskCache.containsKey(cacheKey);

  /// Returns the local file path for a cached entry, or `null`.
  String? getCachedPath(String cacheKey) => _diskCache.get(cacheKey)?.path;

  /// Lock a cache key to prevent eviction while a player is using it.
  void lockKey(String cacheKey) => _lockedKeys.add(cacheKey);

  /// Unlock a cache key, allowing it to be evicted if needed.
  void unlockKey(String cacheKey) => _lockedKeys.remove(cacheKey);

  /// Whether the given [cacheKey] is currently locked.
  bool isLocked(String cacheKey) => _lockedKeys.contains(cacheKey);

  /// Load the cache manifest from disk (cold-start recovery).
  ///
  /// Call this once after construction to recover cache state from a
  /// previous session. Entries whose files no longer exist on disk
  /// are silently skipped.
  Future<void> loadManifest() async {
    final manifestFile = File('$cacheDirectory/_manifest.json');
    if (!await manifestFile.exists()) return;

    try {
      final content = await manifestFile.readAsString();
      final List<dynamic> entries = json.decode(content) as List<dynamic>;

      for (final entry in entries) {
        final cached = CachedFile.fromJson(entry as Map<String, dynamic>);
        // Only restore entries whose files still exist on disk.
        if (await File(cached.path).exists()) {
          _diskCache.put(cached.cacheKey, cached);
          _currentCacheSizeBytes += cached.sizeBytes;
        }
      }
    } catch (_) {
      // Manifest is corrupt or unreadable — start fresh.
    }
  }

  /// Pre-fetch the first [bytesToFetch] bytes of [source] to disk.
  ///
  /// Returns the local file path on success, or `null` on failure / cancel.
  /// If the file is already cached, returns the cached path immediately.
  ///
  /// Multiple calls for the same cache key while a download is in-progress
  /// will share the same future (de-duplication).
  Future<String?> prefetch(
    VideoSource source, {
    int bytesToFetch = 2 * 1024 * 1024,
  }) async {
    if (_disposed) return null;

    final key = source.cacheKey;

    // Already cached.
    final existing = _diskCache.get(key);
    if (existing != null) return existing.path;

    // Already in-flight — return the shared future.
    if (_activeFetches.containsKey(key)) {
      return _activeFetches[key]!.future;
    }

    final completer = Completer<String?>();
    _activeFetches[key] = completer;

    try {
      await _evictIfNeeded(bytesToFetch);

      // Ensure cache directory exists before writing.
      await Directory(cacheDirectory).create(recursive: true);

      final destPath = _filePathForKey(key);

      final result = await Isolate.run<_DownloadResult>(
        () => _downloadInIsolate(
          _DownloadParams(
            url: source.url,
            destPath: destPath,
            headers: source.headers,
            bytesToFetch: bytesToFetch,
            connectionTimeoutSeconds: connectionTimeoutSeconds,
          ),
        ),
      );

      if (_disposed || completer.isCompleted) {
        if (!completer.isCompleted) completer.complete(null);
        return null;
      }

      if (result.error != null) {
        // Clean up partial file on error.
        await _deleteFile(result.path);
        if (!completer.isCompleted) completer.complete(null);
        return null;
      }

      final cached = CachedFile(
        path: result.path,
        sizeBytes: result.sizeBytes,
        cachedAt: DateTime.now(),
        cacheKey: key,
      );

      _diskCache.put(key, cached);
      _currentCacheSizeBytes += result.sizeBytes;

      // Persist manifest for cold-start recovery.
      await _saveManifest();

      if (!completer.isCompleted) completer.complete(result.path);
      return result.path;
    } catch (_) {
      if (!completer.isCompleted) completer.complete(null);
      return null;
    } finally {
      _activeFetches.remove(key);
    }
  }

  /// Cancel an ongoing prefetch for [cacheKey].
  ///
  /// If no fetch is in progress for this key, this is a no-op.
  /// Note: once an isolate is running it cannot be interrupted, but
  /// the result will be discarded.
  void cancelPrefetch(String cacheKey) {
    final completer = _activeFetches.remove(cacheKey);
    if (completer != null && !completer.isCompleted) {
      completer.complete(null);
    }
  }

  /// Clear the entire disk cache and reset size tracking.
  Future<void> clearCache() async {
    _activeFetches.clear();

    for (final entry in _diskCache.entries.toList()) {
      await _deleteFile(entry.value.path);
    }

    _diskCache.clear();
    _lockedKeys.clear();
    _currentCacheSizeBytes = 0;

    await _deleteFile('$cacheDirectory/_manifest.json');
  }

  /// Evict the least-recently-used entries until there is room for
  /// [additionalBytes] without exceeding [maxCacheSizeBytes].
  ///
  /// Locked keys are skipped to prevent eviction of files in active use.
  Future<void> _evictIfNeeded(int additionalBytes) async {
    while (_currentCacheSizeBytes + additionalBytes > maxCacheSizeBytes &&
        _diskCache.length > 0) {
      // Find the oldest unlocked key.
      String? oldestUnlockedKey;
      for (final key in _diskCache.keys) {
        if (!_lockedKeys.contains(key)) {
          oldestUnlockedKey = key;
          break;
        }
      }

      // All entries are locked — cannot evict.
      if (oldestUnlockedKey == null) break;

      final oldest = _diskCache.remove(oldestUnlockedKey);
      if (oldest != null) {
        _currentCacheSizeBytes -= oldest.sizeBytes;
        await _deleteFile(oldest.path);
      }
    }
  }

  /// Release all resources and cancel ongoing prefetches.
  Future<void> dispose() async {
    _disposed = true;

    for (final completer in _activeFetches.values) {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    }
    _activeFetches.clear();
    _lockedKeys.clear();
  }

  // ──────────────────────────── Helpers ──────────────────────────────────

  /// Build a deterministic file path from a cache key.
  ///
  /// Uses SHA-256 hash for collision-resistant, filesystem-safe filenames.
  String _filePathForKey(String key) {
    final hash = sha256.convert(utf8.encode(key)).toString();
    return '$cacheDirectory/vp_$hash.tmp';
  }

  /// Persist the cache manifest to disk for cold-start recovery.
  Future<void> _saveManifest() async {
    try {
      final entries = _diskCache.entries
          .map((e) => e.value.toJson())
          .toList();
      final manifestFile = File('$cacheDirectory/_manifest.json');
      await manifestFile.writeAsString(json.encode(entries));
    } catch (_) {
      // Best-effort persistence.
    }
  }

  /// Delete a file at [path] if it exists. Errors are silently ignored.
  Future<void> _deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort deletion.
    }
  }

  /// Top-level / static function that runs inside an isolate.
  ///
  /// Downloads up to [params.bytesToFetch] bytes from [params.url] and writes
  /// them to [params.destPath]. Validates HTTP status codes and enforces
  /// connection timeout.
  static Future<_DownloadResult> _downloadInIsolate(
    _DownloadParams params,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = Duration(seconds: params.connectionTimeoutSeconds);
    IOSink? sink;
    try {
      final request = await client.getUrl(Uri.parse(params.url));
      for (final entry in params.headers.entries) {
        request.headers.set(entry.key, entry.value);
      }
      // Request only the first N bytes if the server supports range requests.
      request.headers.set('Range', 'bytes=0-${params.bytesToFetch - 1}');

      final response = await request.close();

      // Only accept 200 (OK) or 206 (Partial Content).
      if (response.statusCode != 200 && response.statusCode != 206) {
        // Drain the response to free resources.
        await response.drain<void>();
        return _DownloadResult(
          path: params.destPath,
          sizeBytes: 0,
          error: 'HTTP ${response.statusCode}',
        );
      }

      final file = File(params.destPath);
      final fileSink = file.openWrite();
      sink = fileSink;
      var totalBytes = 0;

      await for (final chunk in response) {
        try {
          fileSink.add(chunk);
        } catch (e) {
          // Disk write error — delete partial file.
          await fileSink.close().catchError((_) => fileSink);
          sink = null;
          try { await file.delete(); } catch (_) {}
          return _DownloadResult(
            path: params.destPath,
            sizeBytes: 0,
            error: 'Disk write error: $e',
          );
        }
        totalBytes += chunk.length;
        if (totalBytes >= params.bytesToFetch) break;
      }

      await fileSink.flush();
      await fileSink.close();
      sink = null;

      return _DownloadResult(path: params.destPath, sizeBytes: totalBytes);
    } catch (e) {
      // Clean up partial file on error.
      try {
        if (sink != null) {
          await sink.close().catchError((_) => sink);
        }
        final partialFile = File(params.destPath);
        if (await partialFile.exists()) {
          await partialFile.delete();
        }
      } catch (_) {}
      return _DownloadResult(path: params.destPath, sizeBytes: 0, error: '$e');
    } finally {
      client.close();
    }
  }
}
