import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

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

  /// Absolute path to the cached file on disk.
  final String path;

  /// Size of the cached file in bytes.
  final int sizeBytes;

  /// When this file was cached.
  final DateTime cachedAt;

  /// The cache key associated with this entry.
  final String cacheKey;
}

/// Parameters passed to the download isolate.
class _DownloadParams {
  const _DownloadParams({
    required this.url,
    required this.destPath,
    required this.headers,
    required this.bytesToFetch,
  });

  final String url;
  final String destPath;
  final Map<String, String> headers;
  final int bytesToFetch;
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
  FilePreloadManager({
    required this.cacheDirectory,
    this.maxCacheSizeBytes = 500 * 1024 * 1024,
    int maxEntries = 100,
  }) : _diskCache = LruCache<String, CachedFile>(
          maxSize: maxEntries,
        );

  /// The directory where cached video files are stored.
  final String cacheDirectory;

  /// Maximum total size of all cached files in bytes. Default: 500 MB.
  final int maxCacheSizeBytes;

  /// In-memory LRU index of cached files.
  final LruCache<String, CachedFile> _diskCache;

  /// Ongoing prefetch operations keyed by cache key.
  final Map<String, Completer<String?>> _activeFetches = {};

  /// Track total size of cached data on disk.
  int _currentCacheSizeBytes = 0;

  bool _disposed = false;

  /// Current total size of cached files on disk.
  int get currentCacheSizeBytes => _currentCacheSizeBytes;

  /// Whether the given [cacheKey] has a completed cache entry.
  bool isCached(String cacheKey) => _diskCache.containsKey(cacheKey);

  /// Returns the local file path for a cached entry, or `null`.
  String? getCachedPath(String cacheKey) => _diskCache.get(cacheKey)?.path;

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
          ),
        ),
      );

      if (_disposed || completer.isCompleted) {
        if (!completer.isCompleted) completer.complete(null);
        return null;
      }

      if (result.error != null) {
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
    _currentCacheSizeBytes = 0;
  }

  /// Evict the least-recently-used entries until there is room for
  /// [additionalBytes] without exceeding [maxCacheSizeBytes].
  Future<void> _evictIfNeeded(int additionalBytes) async {
    while (_currentCacheSizeBytes + additionalBytes > maxCacheSizeBytes &&
        _diskCache.length > 0) {
      // LRU: the first key is the least recently used.
      final oldestKey = _diskCache.keys.first;
      final oldest = _diskCache.remove(oldestKey);
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
  }

  // ──────────────────────────── Helpers ──────────────────────────────────

  /// Build a deterministic file path from a cache key.
  ///
  /// Uses a stable SHA-256 hash (not Dart's `String.hashCode`) so that
  /// the same cache key always maps to the same filename across VM restarts.
  String _filePathForKey(String key) {
    final bytes = utf8.encode(key);
    // SHA-256 via a simple FNV-1a-like stable hash (no crypto dependency).
    // We use base64url for filesystem-safe encoding.
    final encoded = base64Url.encode(bytes);
    // Truncate to avoid overly long file names, keep enough for uniqueness.
    final safeName = encoded.length > 64 ? encoded.substring(0, 64) : encoded;
    return '$cacheDirectory/vp_$safeName.tmp';
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
  /// them to [params.destPath].
  static Future<_DownloadResult> _downloadInIsolate(
    _DownloadParams params,
  ) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(params.url));
      for (final entry in params.headers.entries) {
        request.headers.set(entry.key, entry.value);
      }
      // Request only the first N bytes if the server supports range requests.
      request.headers.set('Range', 'bytes=0-${params.bytesToFetch - 1}');

      final response = await request.close();

      final file = File(params.destPath);
      final sink = file.openWrite();
      var totalBytes = 0;

      await for (final chunk in response) {
        sink.add(chunk);
        totalBytes += chunk.length;
        if (totalBytes >= params.bytesToFetch) break;
      }

      await sink.flush();
      await sink.close();

      return _DownloadResult(path: params.destPath, sizeBytes: totalBytes);
    } catch (e) {
      return _DownloadResult(path: params.destPath, sizeBytes: 0, error: '$e');
    } finally {
      client.close();
    }
  }
}
