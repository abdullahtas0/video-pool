import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_pool/video_pool.dart';

/// Short, real video clips that load fast on emulators and devices.
/// These are from Cloudflare's public test streams and Google samples.
final _videos = [
  const VideoSource(
    url:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
    thumbnailUrl:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerBlazes.jpg',
    resolutionHint: ResolutionHint.hd720,
  ),
  const VideoSource(
    url:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4',
    thumbnailUrl:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerEscapes.jpg',
    resolutionHint: ResolutionHint.hd720,
  ),
  const VideoSource(
    url:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4',
    thumbnailUrl:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerFun.jpg',
    resolutionHint: ResolutionHint.hd720,
  ),
  const VideoSource(
    url:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyrides.mp4',
    thumbnailUrl:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerJoyrides.jpg',
    resolutionHint: ResolutionHint.hd720,
  ),
  const VideoSource(
    url:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4',
    thumbnailUrl:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerMeltdowns.jpg',
    resolutionHint: ResolutionHint.hd720,
  ),
];

/// TikTok / Reels style full-screen vertical video feed.
///
/// Demonstrates disk caching with [FilePreloadManager]: the first 2 MB of
/// upcoming videos are pre-fetched to local storage for instant playback.
class TikTokExample extends StatefulWidget {
  const TikTokExample({super.key});

  @override
  State<TikTokExample> createState() => _TikTokExampleState();
}

class _TikTokExampleState extends State<TikTokExample> {
  FilePreloadManager? _cacheManager;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _initCache();
  }

  Future<void> _initCache() async {
    final cacheDir = await getTemporaryDirectory();
    final manager = FilePreloadManager(
      cacheDirectory: '${cacheDir.path}/video_pool_cache',
    );
    // Recover cached files from a previous session.
    await manager.loadManifest();
    if (mounted) {
      setState(() {
        _cacheManager = manager;
        _ready = true;
      });
    }
  }

  @override
  void dispose() {
    _cacheManager?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return Scaffold(
        appBar: AppBar(title: const Text('TikTok Feed')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

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
        filePreloadManager: _cacheManager,
        child: VideoFeedView(sources: _videos),
      ),
    );
  }
}
