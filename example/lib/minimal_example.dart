// The smallest possible video_pool app: a full-screen, TikTok-style feed.
//
// Run it with:  flutter run -t lib/minimal_example.dart
//
// For the full-featured showcase (Feed / Discover / Insights tabs, disk cache,
// device monitoring, live metrics), run the default entrypoint: lib/main.dart.

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:video_pool/video_pool.dart';

const _videos = [
  VideoSource(
    url: 'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
  ),
  VideoSource(
    url:
        'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4',
  ),
  VideoSource(
    url:
        'https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4',
  ),
];

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MaterialApp(home: _MinimalFeed()));
}

class _MinimalFeed extends StatelessWidget {
  const _MinimalFeed();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // That's it — a reusable 3-player pool driving an infinite feed.
      body: VideoPoolScope(
        config: const VideoPoolConfig(maxConcurrent: 3, preloadCount: 1),
        adapterFactory: (_) => MediaKitAdapter(),
        sourceResolver: (index) =>
            _videos[index % _videos.length], // wrap for an "endless" feed
        child: VideoFeedView(
          sources: List.generate(50, (i) => _videos[i % _videos.length]),
        ),
      ),
    );
  }
}
