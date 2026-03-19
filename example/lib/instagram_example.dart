import 'package:flutter/material.dart';
import 'package:video_pool/video_pool.dart';

/// Short video clips for the Instagram-style feed.
final _videos = [
  const VideoSource(
    url:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
    thumbnailUrl:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerBlazes.jpg',
  ),
  const VideoSource(
    url:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4',
    thumbnailUrl:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerEscapes.jpg',
  ),
  const VideoSource(
    url:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4',
    thumbnailUrl:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerFun.jpg',
  ),
];

/// Instagram-style mixed content feed.
///
/// Shows how to use [VideoListView] with a custom [itemBuilder] to mix
/// video cards with non-video content (text posts, images, etc.).
class InstagramExample extends StatelessWidget {
  const InstagramExample({super.key});

  /// Total items in the feed: alternates between text and video.
  static const _totalItems = 9;

  /// Returns the video index for an item position, or -1 if the item
  /// is not a video.
  static int _videoIndexForItem(int item) {
    // Items at even indices (0, 2, 4, ...) are text posts.
    // Items at odd indices (1, 3, 5, ...) are video posts.
    if (item.isOdd) {
      final videoIdx = item ~/ 2;
      return videoIdx < _videos.length ? videoIdx : -1;
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Instagram Feed')),
      body: VideoPoolScope(
        config: const VideoPoolConfig(
          maxConcurrent: 2,
          preloadCount: 1,
          logLevel: LogLevel.debug,
        ),
        adapterFactory: (_) => MediaKitAdapter(),
        sourceResolver: (index) {
          // Map list-level indices to video sources.
          // The pool sees list indices (0, 1, 2, 3, ...) from the
          // VisibilityTracker, so the resolver must handle the
          // list-to-video mapping (odd indices are videos).
          final videoIdx = _videoIndexForItem(index);
          return videoIdx >= 0 ? _videos[videoIdx] : null;
        },
        child: VideoListView(
          itemCount: _totalItems,
          itemExtent: 400,
          itemBuilder: (context, index) {
            final videoIdx = _videoIndexForItem(index);
            if (videoIdx >= 0) {
              return SizedBox(
                height: 400,
                child: VideoCard(
                  // Use the list-level index (not videoIdx) so it matches
                  // what the pool's VisibilityTracker reports.
                  index: index,
                  source: _videos[videoIdx],
                ),
              );
            }
            // Non-video content
            return Container(
              height: 400,
              padding: const EdgeInsets.all(24),
              child: Card(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.article, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        'Text Post #${index ~/ 2 + 1}',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      const Text('This is a non-video item in the feed.'),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
