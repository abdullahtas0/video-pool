import 'package:flutter/material.dart';
import 'package:video_pool/video_pool.dart';

/// An aggressive battery-saver lifecycle policy.
///
/// - Preloads 0 items (saves battery and bandwidth).
/// - Immediately releases anything that is not the primary video.
class AggressivePolicy implements LifecyclePolicy {
  const AggressivePolicy();

  @override
  ReconciliationPlan reconcile({
    required int primaryIndex,
    required Map<int, double> visibilityRatios,
    required int effectiveMaxConcurrent,
    required int effectivePreloadCount,
    required Set<int> currentlyActive,
  }) {
    // Only play the primary index, release everything else.
    final toRelease = <int>{};
    for (final index in currentlyActive) {
      if (index != primaryIndex) {
        toRelease.add(index);
      }
    }

    return ReconciliationPlan(
      toPlay: {primaryIndex},
      toRelease: toRelease,
    );
  }
}

/// Short video clips.
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

/// Demonstrates a custom [LifecyclePolicy] for battery-saving scenarios.
///
/// Uses [AggressivePolicy] which only keeps the primary video alive,
/// immediately releasing all others. This is ideal for users on low
/// battery or metered connections.
class CustomPolicyExample extends StatelessWidget {
  const CustomPolicyExample({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Custom Policy (Battery Saver)'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: VideoPoolScope(
        config: const VideoPoolConfig(
          maxConcurrent: 2,
          preloadCount: 0,
          lifecyclePolicy: AggressivePolicy(),
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
