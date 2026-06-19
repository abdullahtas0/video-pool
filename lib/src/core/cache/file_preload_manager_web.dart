import '../models/video_source.dart';

/// Web stub for [FilePreloadManager].
///
/// The browser has no writable filesystem for a video disk cache, so this
/// implementation is an inert no-op with the exact same public API as the
/// native [FilePreloadManager] in `file_preload_manager_io.dart`. Every query
/// reports "not cached", every prefetch resolves to `null`, and the pool
/// therefore opens network URLs directly. Keeping the API identical means
/// `VideoPool` and `VideoPoolScope` compile and run unchanged on web.
class FilePreloadManager {
  /// Creates a no-op [FilePreloadManager] (web).
  FilePreloadManager({
    required this.cacheDirectory,
    this.maxCacheSizeBytes = 500 * 1024 * 1024,
    int maxEntries = 100,
    this.connectionTimeoutSeconds = 15,
  });

  /// The directory where cached video files would be stored (unused on web).
  final String cacheDirectory;

  /// Maximum total size of all cached files in bytes. Default: 500 MB.
  final int maxCacheSizeBytes;

  /// HTTP connection timeout in seconds.
  final int connectionTimeoutSeconds;

  /// Keys locked by a player. Tracked so lock/unlock/isLocked stay consistent.
  final Set<String> _lockedKeys = {};

  /// Always `0` — no files are cached on web.
  int get currentCacheSizeBytes => 0;

  /// Always `false` on web.
  bool isCached(String cacheKey) => false;

  /// Always `null` on web.
  String? getCachedPath(String cacheKey) => null;

  /// Always `null` on web.
  String? getThumbnailPath(String cacheKey) => null;

  /// Lock a cache key. Harmless on web; kept for API parity.
  void lockKey(String cacheKey) => _lockedKeys.add(cacheKey);

  /// Unlock a cache key.
  void unlockKey(String cacheKey) => _lockedKeys.remove(cacheKey);

  /// Whether the given [cacheKey] is currently locked.
  bool isLocked(String cacheKey) => _lockedKeys.contains(cacheKey);

  /// No-op on web (no manifest to load).
  Future<void> loadManifest() async {}

  /// No-op on web (nothing to clean up).
  Future<void> cleanupIncomplete({
    Duration maxAge = const Duration(hours: 24),
  }) async {}

  /// Always resolves to `null` on web — the caller falls back to the network
  /// URL, which the browser streams directly.
  Future<String?> prefetch(
    VideoSource source, {
    int bytesToFetch = 2 * 1024 * 1024,
  }) async =>
      null;

  /// No-op on web.
  void cancelPrefetch(String cacheKey) {}

  /// No-op on web.
  Future<void> clearCache() async {}

  /// No-op on web.
  Future<void> dispose() async {
    _lockedKeys.clear();
  }
}
