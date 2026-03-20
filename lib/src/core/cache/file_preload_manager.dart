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
    this.complete = true,
    this.etag,
    int? targetBytes,
    this.lastCheckedAt,
  }) : targetBytes = targetBytes ?? sizeBytes;

  /// Creates a [CachedFile] from a JSON map (for manifest deserialization).
  ///
  /// Backward-compatible: old manifests without `complete`, `etag`,
  /// `targetBytes`, or `lastCheckedAt` fields will parse with safe defaults.
  factory CachedFile.fromJson(Map<String, dynamic> json) {
    final sizeBytes = json['sizeBytes'] as int;
    return CachedFile(
      path: json['path'] as String,
      sizeBytes: sizeBytes,
      cachedAt: DateTime.parse(json['cachedAt'] as String),
      cacheKey: json['cacheKey'] as String,
      complete: json['complete'] as bool? ?? true,
      etag: json['etag'] as String?,
      targetBytes: json['targetBytes'] as int? ?? sizeBytes,
      lastCheckedAt: json['lastCheckedAt'] != null
          ? DateTime.parse(json['lastCheckedAt'] as String)
          : null,
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

  /// Whether the download completed successfully.
  /// `false` means the file is a partial download eligible for resume.
  final bool complete;

  /// ETag from the server response, used for resume validation via If-Range.
  final String? etag;

  /// How many bytes we intended to download (e.g. 2MB).
  final int targetBytes;

  /// When this entry was last checked/attempted for resume.
  /// Used by janitor cleanup to remove stale incomplete entries.
  final DateTime? lastCheckedAt;

  /// Converts this to a JSON map (for manifest serialization).
  Map<String, dynamic> toJson() => {
        'path': path,
        'sizeBytes': sizeBytes,
        'cachedAt': cachedAt.toIso8601String(),
        'cacheKey': cacheKey,
        'complete': complete,
        'etag': etag,
        'targetBytes': targetBytes,
        'lastCheckedAt': lastCheckedAt?.toIso8601String(),
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
    this.resumeFromByte = 0,
    this.etag,
  });

  final String url;
  final String destPath;
  final Map<String, String> headers;
  final int bytesToFetch;
  final int connectionTimeoutSeconds;

  /// Byte offset to resume from. 0 = fresh download.
  final int resumeFromByte;

  /// ETag from a previous partial download, used for If-Range validation.
  final String? etag;
}

/// Result returned from the download isolate.
class _DownloadResult {
  const _DownloadResult({
    required this.path,
    required this.sizeBytes,
    this.error,
    this.etag,
  });

  final String path;
  final int sizeBytes;
  final String? error;

  /// ETag from the server response headers, stored for future resume.
  final String? etag;
}

/// Manages pre-fetching video data to disk so that the player can open
/// local files instead of streaming from the network.
///
/// Downloads run in a separate isolate to avoid blocking the UI thread.
/// An [LruCache] tracks entries and evicts the oldest when the cache
/// exceeds [maxCacheSizeBytes].
///
/// Supports progressive download resume: if a download is interrupted,
/// the partial file is kept and subsequent attempts resume from where
/// they left off using HTTP Range headers.
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

  /// Consecutive resume failure counts per cache key.
  final Map<String, int> _retryCount = {};

  bool _disposed = false;

  /// Current total size of cached files on disk.
  int get currentCacheSizeBytes => _currentCacheSizeBytes;

  /// Whether the given [cacheKey] has a completed cache entry.
  bool isCached(String cacheKey) => _diskCache.containsKey(cacheKey);

  /// Returns the local file path for a completed cached entry, or `null`.
  ///
  /// Partial (incomplete) files are not returned — they are not safe for
  /// playback and are only used internally for download resume.
  String? getCachedPath(String cacheKey) {
    final cached = _diskCache.get(cacheKey);
    if (cached == null || !cached.complete) return null;
    return cached.path;
  }

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
  ///
  /// After loading, runs [cleanupIncomplete] to remove stale partial files.
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

    await cleanupIncomplete();
  }

  /// Remove incomplete cache entries older than [maxAge].
  ///
  /// Called automatically at the end of [loadManifest], or can be called
  /// periodically to clean up stale partial downloads.
  Future<void> cleanupIncomplete({
    Duration maxAge = const Duration(hours: 24),
  }) async {
    final now = DateTime.now();
    final toRemove = <String>[];

    for (final entry in _diskCache.entries) {
      final cached = entry.value;
      if (!cached.complete) {
        final age = cached.lastCheckedAt ?? cached.cachedAt;
        if (now.difference(age) > maxAge) {
          toRemove.add(entry.key);
        }
      }
    }

    for (final key in toRemove) {
      final cached = _diskCache.remove(key);
      if (cached != null) {
        await _deleteFile(cached.path);
        _currentCacheSizeBytes -= cached.sizeBytes;
      }
    }

    if (toRemove.isNotEmpty) await _saveManifest();
  }

  /// Pre-fetch the first [bytesToFetch] bytes of [source] to disk.
  ///
  /// Returns the local file path on success, or `null` on failure / cancel.
  /// If the file is already cached (and complete), returns the cached path
  /// immediately.
  ///
  /// If a partial (incomplete) cached file exists, attempts to resume the
  /// download from where it left off using HTTP Range headers. After 3
  /// consecutive resume failures for the same key, the partial file is
  /// deleted and `null` is returned.
  ///
  /// Multiple calls for the same cache key while a download is in-progress
  /// will share the same future (de-duplication).
  Future<String?> prefetch(
    VideoSource source, {
    int bytesToFetch = 2 * 1024 * 1024,
  }) async {
    if (_disposed) return null;

    final key = source.cacheKey;

    // Already cached and complete.
    final existing = _diskCache.get(key);
    if (existing != null && existing.complete) return existing.path;

    // Already in-flight — return the shared future.
    if (_activeFetches.containsKey(key)) {
      return _activeFetches[key]!.future;
    }

    final completer = Completer<String?>();
    _activeFetches[key] = completer;

    try {
      // Determine resume parameters from existing partial entry.
      int resumeFromByte = 0;
      String? resumeEtag;

      if (existing != null && !existing.complete) {
        // Check if partial file still exists on disk.
        final partialFile = File(existing.path);
        if (await partialFile.exists()) {
          resumeFromByte = existing.sizeBytes;
          resumeEtag = existing.etag;
        } else {
          // Partial entry exists in manifest but file is gone — remove it.
          _diskCache.remove(key);
          _currentCacheSizeBytes -= existing.sizeBytes;
        }
      }

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
            resumeFromByte: resumeFromByte,
            etag: resumeEtag,
          ),
        ),
      );

      if (_disposed || completer.isCompleted) {
        if (!completer.isCompleted) completer.complete(null);
        return null;
      }

      if (result.error != null) {
        // Increment retry count for resume failures.
        _retryCount[key] = (_retryCount[key] ?? 0) + 1;

        if (_retryCount[key]! >= 3) {
          // Too many failures — give up, delete partial, clean up.
          await _deleteFile(result.path);
          final partial = _diskCache.remove(key);
          if (partial != null) {
            _currentCacheSizeBytes -= partial.sizeBytes;
          }
          _retryCount.remove(key);
          await _saveManifest();
          if (!completer.isCompleted) completer.complete(null);
          return null;
        }

        // Save partial file as incomplete entry for future resume.
        // Only if the file exists and has some data.
        final partialFile = File(result.path);
        if (await partialFile.exists()) {
          final partialSize = await partialFile.length();
          if (partialSize > 0) {
            // Remove old entry size tracking before adding new.
            final oldEntry = _diskCache.remove(key);
            if (oldEntry != null) {
              _currentCacheSizeBytes -= oldEntry.sizeBytes;
            }

            final partial = CachedFile(
              path: result.path,
              sizeBytes: partialSize,
              cachedAt: DateTime.now(),
              cacheKey: key,
              complete: false,
              etag: result.etag,
              targetBytes: bytesToFetch,
              lastCheckedAt: DateTime.now(),
            );
            _diskCache.put(key, partial);
            _currentCacheSizeBytes += partialSize;
            await _saveManifest();
          }
        }

        if (!completer.isCompleted) completer.complete(null);
        return null;
      }

      // Success — reset retry count.
      _retryCount.remove(key);

      // Remove old partial entry size tracking if present.
      final oldEntry = _diskCache.remove(key);
      if (oldEntry != null) {
        _currentCacheSizeBytes -= oldEntry.sizeBytes;
      }

      final cached = CachedFile(
        path: result.path,
        sizeBytes: result.sizeBytes,
        cachedAt: DateTime.now(),
        cacheKey: key,
        complete: true,
        etag: result.etag,
        targetBytes: bytesToFetch,
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
    _retryCount.clear();
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
    _retryCount.clear();
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
  ///
  /// Supports resume: if [params.resumeFromByte] > 0, sends Range and
  /// If-Range headers to continue a previous partial download.
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

      final isResume = params.resumeFromByte > 0 && params.etag != null;

      if (isResume) {
        // Resume: request from resumeFromByte to bytesToFetch.
        request.headers.set(
          'Range',
          'bytes=${params.resumeFromByte}-${params.bytesToFetch - 1}',
        );
        request.headers.set('If-Range', params.etag!);
      } else {
        // Fresh download: request first N bytes.
        request.headers.set('Range', 'bytes=0-${params.bytesToFetch - 1}');
      }

      final response = await request.close();

      // Extract ETag from response headers.
      final responseEtag = response.headers.value('etag');

      if (isResume) {
        if (response.statusCode == 206) {
          // Server supports resume — append to existing file.
          final file = File(params.destPath);
          final fileSink = file.openWrite(mode: FileMode.append);
          sink = fileSink;
          var totalBytes = params.resumeFromByte;

          await for (final chunk in response) {
            try {
              fileSink.add(chunk);
            } catch (e) {
              await fileSink.close().catchError((_) => fileSink);
              sink = null;
              return _DownloadResult(
                path: params.destPath,
                sizeBytes: params.resumeFromByte,
                error: 'Disk write error: $e',
                etag: responseEtag,
              );
            }
            totalBytes += chunk.length;
            if (totalBytes >= params.bytesToFetch) break;
          }

          await fileSink.flush();
          await fileSink.close();
          sink = null;

          return _DownloadResult(
            path: params.destPath,
            sizeBytes: totalBytes,
            etag: responseEtag,
          );
        } else if (response.statusCode == 200) {
          // Server doesn't support resume or content changed — start fresh.
          // Delete existing partial file and write from scratch.
          try {
            final existing = File(params.destPath);
            if (await existing.exists()) await existing.delete();
          } catch (_) {}

          return _downloadFresh(
            params: params,
            response: response,
            client: client,
            responseEtag: responseEtag,
          );
        } else {
          // 412 Precondition Failed or 416 Range Not Satisfiable:
          // content changed, delete file and signal error to retry fresh.
          await response.drain<void>();
          try {
            final existing = File(params.destPath);
            if (await existing.exists()) await existing.delete();
          } catch (_) {}
          return _DownloadResult(
            path: params.destPath,
            sizeBytes: 0,
            error: 'HTTP ${response.statusCode} — resume rejected',
            etag: responseEtag,
          );
        }
      }

      // Non-resume path: standard download.
      // Only accept 200 (OK) or 206 (Partial Content).
      if (response.statusCode != 200 && response.statusCode != 206) {
        await response.drain<void>();
        return _DownloadResult(
          path: params.destPath,
          sizeBytes: 0,
          error: 'HTTP ${response.statusCode}',
        );
      }

      return _downloadFresh(
        params: params,
        response: response,
        client: client,
        responseEtag: responseEtag,
      );
    } catch (e) {
      // Clean up partial file on error — but keep it for resume if it exists.
      try {
        if (sink != null) {
          await sink.close().catchError((_) => sink);
        }
      } catch (_) {}

      // Check if we have any partial data worth keeping for resume.
      int partialSize = 0;
      try {
        final partialFile = File(params.destPath);
        if (await partialFile.exists()) {
          partialSize = await partialFile.length();
        }
      } catch (_) {}

      return _DownloadResult(
        path: params.destPath,
        sizeBytes: partialSize,
        error: '$e',
      );
    } finally {
      client.close();
    }
  }

  /// Writes response data to a fresh file (no append).
  ///
  /// Extracted to avoid code duplication between fresh downloads
  /// and resume-rejected-fallback-to-fresh scenarios.
  static Future<_DownloadResult> _downloadFresh({
    required _DownloadParams params,
    required HttpClientResponse response,
    required HttpClient client,
    required String? responseEtag,
  }) async {
    final file = File(params.destPath);
    final fileSink = file.openWrite();
    var totalBytes = 0;

    await for (final chunk in response) {
      try {
        fileSink.add(chunk);
      } catch (e) {
        await fileSink.close().catchError((_) => fileSink);
        try {
          await file.delete();
        } catch (_) {}
        return _DownloadResult(
          path: params.destPath,
          sizeBytes: 0,
          error: 'Disk write error: $e',
          etag: responseEtag,
        );
      }
      totalBytes += chunk.length;
      if (totalBytes >= params.bytesToFetch) break;
    }

    await fileSink.flush();
    await fileSink.close();

    return _DownloadResult(
      path: params.destPath,
      sizeBytes: totalBytes,
      etag: responseEtag,
    );
  }
}
