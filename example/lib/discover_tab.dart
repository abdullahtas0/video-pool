import 'package:flutter/material.dart';
import 'package:video_pool/video_pool.dart';

import 'video_sources.dart';

/// Instagram-style mixed content feed with videos and text/image cards.
///
/// Uses its own [VideoPoolScope] with a smaller pool (maxConcurrent: 2)
/// independent from the Feed tab's pool.
class DiscoverTab extends StatelessWidget {
  const DiscoverTab({super.key});

  /// Total items in the feed: alternates between text and video.
  static const _totalItems = 11;

  /// Returns the video index for an item position, or -1 if not a video.
  static int _videoIndexForItem(int item) {
    // Items at even indices (0, 2, 4, ...) are text/image posts.
    // Items at odd indices (1, 3, 5, ...) are video posts.
    if (item.isOdd) {
      final videoIdx = item ~/ 2;
      return videoIdx < discoverVideos.length ? videoIdx : -1;
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    return VideoPoolScope(
      config: const VideoPoolConfig(
        maxConcurrent: 2,
        preloadCount: 1,
        logLevel: LogLevel.info,
      ),
      adapterFactory: (_) => MediaKitAdapter(),
      sourceResolver: (index) {
        final videoIdx = _videoIndexForItem(index);
        return videoIdx >= 0 ? discoverVideos[videoIdx] : null;
      },
      child: VideoListView(
        itemCount: _totalItems,
        itemExtent: 350,
        itemBuilder: (context, index) {
          final videoIdx = _videoIndexForItem(index);
          if (videoIdx >= 0) {
            return _VideoCard(index: index, videoIdx: videoIdx);
          }
          return _ContentCard(index: index);
        },
      ),
    );
  }
}

/// A polished video card for the discover feed.
class _VideoCard extends StatelessWidget {
  const _VideoCard({required this.index, required this.videoIdx});

  final int index;
  final int videoIdx;

  @override
  Widget build(BuildContext context) {
    final source = discoverVideos[videoIdx];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 338,
          color: const Color(0xFF1A1A2E),
          child: Stack(
            fit: StackFit.expand,
            children: [
              VideoCard(
                index: index,
                source: source,
                showOverlay: true,
              ),
              // State badge overlay
              Positioned(
                top: 12,
                left: 12,
                child: _LifecycleBadge(index: index),
              ),
              // Video title
              Positioned(
                bottom: 12,
                left: 12,
                right: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    videoIdx < feedVideoTitles.length
                        ? feedVideoTitles[videoIdx]
                        : 'Video ${videoIdx + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows lifecycle state badge using the pool context.
class _LifecycleBadge extends StatelessWidget {
  const _LifecycleBadge({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final pool = VideoPoolProvider.of(context);

    return ValueListenableBuilder<int>(
      valueListenable: pool.reconciliationNotifier,
      builder: (context, reconcileCount, child) {
        final entry = pool.getEntryForIndex(index);
        if (entry == null) return _badge(LifecycleState.idle);

        return ValueListenableBuilder<LifecycleState>(
          valueListenable: entry.lifecycleNotifier,
          builder: (context, state, _) => _badge(state),
        );
      },
    );
  }

  Widget _badge(LifecycleState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _colorForState(state),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 4,
          ),
        ],
      ),
      child: Text(
        state.name.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Color _colorForState(LifecycleState state) {
    return switch (state) {
      LifecycleState.playing => const Color(0xFF7C4DFF),
      LifecycleState.ready => const Color(0xFF4CAF50),
      LifecycleState.preparing => const Color(0xFF2196F3),
      LifecycleState.buffering => const Color(0xFFFF9800),
      LifecycleState.paused => const Color(0xFF9E9E9E),
      LifecycleState.error => const Color(0xFFF44336),
      _ => const Color(0xFF616161),
    };
  }
}

/// Placeholder content card (text/image post) for the mixed feed.
class _ContentCard extends StatelessWidget {
  const _ContentCard({required this.index});

  final int index;

  static const _cardTitles = [
    'Pool Architecture',
    'Instance Reuse',
    'Thermal Throttling',
    'Disk Caching',
    'Memory Management',
    'Scroll Prediction',
  ];

  static const _cardDescriptions = [
    'A fixed pool of N player instances are created once and recycled via swapSource() — never disposed during scroll.',
    'Eliminates GC pressure and decoder teardown. Players are reused across different video indices.',
    'Thermal and memory levels reduce maxConcurrent and preloadCount at runtime. Critical thermal = 1 player only.',
    'First 2MB of upcoming videos are pre-fetched to local storage for instant playback. 500MB LRU disk cache.',
    'LRU eviction of idle entries. Budget scales down under pressure. Emergency flush keeps only the primary player.',
    'Predictive scroll engine estimates where the scroll will land and triggers prefetch for high-confidence targets.',
  ];

  static const _cardIcons = [
    Icons.architecture,
    Icons.recycling,
    Icons.thermostat,
    Icons.sd_storage,
    Icons.memory,
    Icons.speed,
  ];

  @override
  Widget build(BuildContext context) {
    final cardIdx = (index ~/ 2) % _cardTitles.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Container(
        height: 338,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF7C4DFF).withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C4DFF).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _cardIcons[cardIdx],
                    color: const Color(0xFF7C4DFF),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _cardTitles[cardIdx],
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'video_pool feature',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Text(
                _cardDescriptions[cardIdx],
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),
            const Divider(color: Color(0xFF2A2A3E), height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  color: const Color(0xFF7C4DFF).withValues(alpha: 0.6),
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  'Learn more in the source code',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
