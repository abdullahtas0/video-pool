import 'package:flutter/material.dart';
import 'package:video_pool/video_pool.dart';

/// Sample video URLs (open-source / Creative Commons videos).
final _videos = [
  const VideoSource(
    url:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
  ),
  const VideoSource(
    url:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
  ),
  const VideoSource(
    url:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
  ),
  const VideoSource(
    url:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4',
  ),
  const VideoSource(
    url:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4',
  ),
];

/// TikTok / Reels style full-screen vertical video feed.
///
/// Demonstrates the simplest usage of video_pool: wrap a [VideoFeedView]
/// in a [VideoPoolScope] and you are done.
class TikTokExample extends StatelessWidget {
  const TikTokExample({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('TikTok Feed'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: VideoPoolScope(
        config: const VideoPoolConfig(
          maxConcurrent: 3,
          preloadCount: 1,
          logLevel: LogLevel.info,
        ),
        adapterFactory: (_) => MediaKitAdapter(),
        sourceResolver: (index) =>
            index >= 0 && index < _videos.length ? _videos[index] : null,
        child: VideoFeedView(sources: _videos),
      ),
    );
  }
}
