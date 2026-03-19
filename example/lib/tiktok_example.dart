import 'package:flutter/material.dart';
import 'package:video_pool/video_pool.dart';

/// Short, real video clips that load fast on emulators and devices.
/// These are from Cloudflare's public test streams and Google samples.
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
  const VideoSource(
    url:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyrides.mp4',
    thumbnailUrl:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerJoyrides.jpg',
  ),
  const VideoSource(
    url:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4',
    thumbnailUrl:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerMeltdowns.jpg',
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
          logLevel: LogLevel.debug,
        ),
        adapterFactory: (_) => MediaKitAdapter(),
        sourceResolver: (index) =>
            index >= 0 && index < _videos.length ? _videos[index] : null,
        child: VideoFeedView(sources: _videos),
      ),
    );
  }
}
