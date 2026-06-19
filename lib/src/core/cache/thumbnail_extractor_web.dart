import 'dart:async';

/// Web stub for [ThumbnailExtractor].
///
/// Native thumbnail extraction relies on `dart:io` file access and the
/// `dev.video_pool/thumbnail` platform channel (AVAssetImageGenerator /
/// MediaMetadataRetriever), neither of which exists on web. This stub keeps
/// the exact same public API as `thumbnail_extractor_io.dart` but produces no
/// thumbnails — callers simply fall back to their placeholder UI.
class ThumbnailExtractor {
  /// Creates a no-op [ThumbnailExtractor] (web).
  ThumbnailExtractor({this.maxConcurrent = 1});

  /// Maximum concurrent extraction operations (unused on web).
  final int maxConcurrent;

  bool _disposed = false;

  /// Always `false` on web — FastStart detection needs file access.
  static Future<bool> isFastStart(String filePath) async => false;

  /// Always resolves to `null` on web — no native extractor is available.
  Future<String?> extract({
    required String videoPath,
    required String outputPath,
    int priorityIndex = 0,
  }) async {
    if (_disposed) return null;
    return null;
  }

  /// Marks this extractor disposed.
  void dispose() {
    _disposed = true;
  }
}
