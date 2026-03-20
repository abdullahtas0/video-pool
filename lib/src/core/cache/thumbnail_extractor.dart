import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

/// Extracts thumbnail images from cached video files.
///
/// Uses native platform APIs:
/// - iOS: AVAssetImageGenerator
/// - Android: MediaMetadataRetriever
///
/// Thumbnails are saved as JPEG files alongside the cached video.
class ThumbnailExtractor {
  /// Creates a [ThumbnailExtractor].
  ///
  /// [maxConcurrent] controls how many extraction operations can run
  /// simultaneously. Defaults to 1 to avoid overwhelming the GPU.
  ThumbnailExtractor({this.maxConcurrent = 1});

  /// Maximum concurrent extraction operations.
  final int maxConcurrent;

  int _activeCount = 0;
  final _queue = <_ExtractionTask>[];
  bool _disposed = false;

  static const _channel = MethodChannel('dev.video_pool/thumbnail');

  /// Check if a video file has FastStart format (moov atom at start).
  ///
  /// MP4 files with the moov atom before the mdat atom can begin playback
  /// immediately without downloading the entire file. This is a quick
  /// byte-level check that doesn't require platform channels.
  static Future<bool> isFastStart(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return false;

      final raf = await file.open();
      try {
        // Read first 4096 bytes to find atom headers (ftyp is typically 20-32 bytes,
        // followed by optional free/skip atoms before moov or mdat)
        final header = await raf.read(4096);
        if (header.length < 8) return false;

        // MP4 files start with ftyp atom, then typically moov or free
        // Look for 'moov' atom in first few atoms
        var offset = 0;
        while (offset + 8 <= header.length) {
          final size = (header[offset] << 24) |
              (header[offset + 1] << 16) |
              (header[offset + 2] << 8) |
              header[offset + 3];
          final type =
              String.fromCharCodes(header.sublist(offset + 4, offset + 8));

          if (type == 'moov') return true;
          if (type == 'mdat') return false; // mdat before moov = not FastStart

          if (size <= 0) break;
          offset += size;

          // If moov would be beyond what we read, try to read more
          if (offset + 8 > header.length && offset < 1024) {
            // Read more from the file
            await raf.setPosition(offset);
            final moreHeader = await raf.read(8);
            if (moreHeader.length >= 8) {
              final moreType =
                  String.fromCharCodes(moreHeader.sublist(4, 8));
              if (moreType == 'moov') return true;
              if (moreType == 'mdat') return false;
            }
            break;
          }
        }
        return false;
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }

  /// Extract a thumbnail from a video file.
  ///
  /// Returns the path to the JPEG thumbnail, or `null` on failure.
  ///
  /// Respects [maxConcurrent] — excess requests are queued.
  /// Priority is given to requests with a lower [priorityIndex].
  Future<String?> extract({
    required String videoPath,
    required String outputPath,
    int priorityIndex = 0,
  }) async {
    if (_disposed) return null;

    final completer = Completer<String?>();
    final task = _ExtractionTask(
      videoPath: videoPath,
      outputPath: outputPath,
      priorityIndex: priorityIndex,
      completer: completer,
    );

    _queue.add(task);
    _processQueue();

    return completer.future;
  }

  void _processQueue() {
    while (_activeCount < maxConcurrent && _queue.isNotEmpty) {
      // Sort by priority (lower index = higher priority)
      _queue.sort((a, b) => a.priorityIndex.compareTo(b.priorityIndex));
      final task = _queue.removeAt(0);
      _activeCount++;
      _executeTask(task);
    }
  }

  Future<void> _executeTask(_ExtractionTask task) async {
    try {
      final result = await _channel.invokeMethod<String>('extractThumbnail', {
        'videoPath': task.videoPath,
        'outputPath': task.outputPath,
      });
      task.completer.complete(result);
    } catch (_) {
      task.completer.complete(null);
    } finally {
      _activeCount--;
      if (!_disposed) _processQueue();
    }
  }

  /// Release all resources and complete pending tasks with `null`.
  void dispose() {
    _disposed = true;
    for (final task in _queue) {
      if (!task.completer.isCompleted) {
        task.completer.complete(null);
      }
    }
    _queue.clear();
  }
}

class _ExtractionTask {
  _ExtractionTask({
    required this.videoPath,
    required this.outputPath,
    required this.priorityIndex,
    required this.completer,
  });

  final String videoPath;
  final String outputPath;
  final int priorityIndex;
  final Completer<String?> completer;
}
