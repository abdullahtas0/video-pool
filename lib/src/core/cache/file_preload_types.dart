/// Pure-Dart data types shared by the native and web implementations of
/// [FilePreloadManager]. Contains no `dart:io` dependency so it compiles on
/// every platform.
library;

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
