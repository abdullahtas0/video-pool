import 'package:flutter/material.dart';
import 'package:video_pool/video_pool.dart';

import 'video_sources.dart';

/// TikTok/Reels style full-screen vertical video feed.
///
/// Uses the shared [VideoPool] from the parent via [VideoPoolProvider].
/// Each page shows a polished overlay with title, lifecycle state badge,
/// entry ID, cache status, progress bar, and decorative social buttons.
class FeedTab extends StatelessWidget {
  const FeedTab({super.key});

  @override
  Widget build(BuildContext context) {
    return VideoFeedView(
      sources: feedVideos,
      itemBuilder: (context, index, source) {
        return _FeedPage(index: index, source: source);
      },
    );
  }
}

class _FeedPage extends StatelessWidget {
  const _FeedPage({required this.index, required this.source});

  final int index;
  final VideoSource source;

  @override
  Widget build(BuildContext context) {
    final pool = VideoPoolProvider.of(context);

    return ValueListenableBuilder<int>(
      valueListenable: pool.reconciliationNotifier,
      builder: (context, reconcileCount, child) {
        final entry = pool.getEntryForIndex(index);

        if (entry == null) {
          return _buildWithOverlay(
            context: context,
            child: VideoThumbnail(thumbnailUrl: source.thumbnailUrl),
            lifecycleState: LifecycleState.idle,
            entry: null,
            pool: pool,
          );
        }

        return ValueListenableBuilder<LifecycleState>(
          valueListenable: entry.lifecycleNotifier,
          builder: (context, lifecycleState, _) {
            final Widget content;

            switch (lifecycleState) {
              case LifecycleState.idle:
              case LifecycleState.preloading:
              case LifecycleState.disposed:
                content = VideoThumbnail(thumbnailUrl: source.thumbnailUrl);
              case LifecycleState.preparing:
                content = Stack(
                  fit: StackFit.expand,
                  children: [
                    VideoThumbnail(thumbnailUrl: source.thumbnailUrl),
                    const Center(
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3.0,
                      ),
                    ),
                  ],
                );
              case LifecycleState.ready:
                content = Stack(
                  fit: StackFit.expand,
                  children: [
                    entry.adapter.videoWidget,
                    VideoThumbnail(thumbnailUrl: source.thumbnailUrl),
                  ],
                );
              case LifecycleState.playing:
              case LifecycleState.paused:
              case LifecycleState.buffering:
                content = entry.adapter.videoWidget;
              case LifecycleState.error:
                content = VideoErrorWidget(
                  onRetry: () {
                    pool.onVisibilityChanged(
                      primaryIndex: index,
                      visibilityRatios: {index: 1.0},
                    );
                  },
                );
            }

            return _buildWithOverlay(
              context: context,
              child: content,
              lifecycleState: lifecycleState,
              entry: entry,
              pool: pool,
            );
          },
        );
      },
    );
  }

  Widget _buildWithOverlay({
    required BuildContext context,
    required Widget child,
    required LifecycleState lifecycleState,
    required PoolEntry? entry,
    required VideoPool pool,
  }) {
    return GestureDetector(
      onTap: () => pool.togglePlayPause(index),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Video / thumbnail
          child,

          // Gradient overlay at bottom
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 200,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.7),
                  ],
                ),
              ),
            ),
          ),

          // Bottom-left info
          Positioned(
            left: 16,
            bottom: 24,
            right: 72,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Title
                Text(
                  index < feedVideoTitles.length
                      ? feedVideoTitles[index]
                      : 'Video ${index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                // State badges row
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _StateBadge(state: lifecycleState),
                    if (entry != null)
                      _InfoBadge(
                        label: 'ENTRY #${entry.id}',
                        color: const Color(0xFF2196F3),
                      ),
                    _InfoBadge(
                      label: _cacheStatusLabel(entry),
                      color: _cacheStatusColor(entry),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Right side social buttons
          Positioned(
            right: 16,
            bottom: 80,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SocialButton(
                  icon: Icons.favorite_outline,
                  label: '${(index + 1) * 12}K',
                ),
                const SizedBox(height: 20),
                _SocialButton(
                  icon: Icons.chat_bubble_outline,
                  label: '${(index + 1) * 3}K',
                ),
                const SizedBox(height: 20),
                _SocialButton(
                  icon: Icons.send_outlined,
                  label: '${index * 8 + 5}',
                ),
                const SizedBox(height: 20),
                const _SocialButton(
                  icon: Icons.bookmark_outline,
                  label: 'Save',
                ),
              ],
            ),
          ),

          // Pause icon overlay
          if (lifecycleState == LifecycleState.paused)
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 36,
                ),
              ),
            ),

          // Buffering indicator
          if (lifecycleState == LifecycleState.buffering)
            const Center(
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3.0,
              ),
            ),

          // Progress bar at bottom
          if (entry != null &&
              (lifecycleState == LifecycleState.playing ||
                  lifecycleState == LifecycleState.paused ||
                  lifecycleState == LifecycleState.buffering))
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _ProgressBar(entry: entry),
            ),
        ],
      ),
    );
  }

  String _cacheStatusLabel(PoolEntry? entry) {
    if (entry == null) return 'WAITING';
    // If the adapter state has a source loaded via file path, it's a cache hit.
    final state = entry.adapter.stateNotifier.value;
    if (state.currentSource?.type == VideoSourceType.file) return 'CACHE HIT';
    if (entry.lifecycleState == LifecycleState.playing ||
        entry.lifecycleState == LifecycleState.paused) {
      return 'NETWORK';
    }
    return 'LOADING';
  }

  Color _cacheStatusColor(PoolEntry? entry) {
    if (entry == null) return Colors.grey;
    final state = entry.adapter.stateNotifier.value;
    if (state.currentSource?.type == VideoSourceType.file) {
      return const Color(0xFF4CAF50);
    }
    return const Color(0xFFFF9800);
  }
}

/// Lifecycle state badge with color coding.
class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.state});

  final LifecycleState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _colorForState(state),
        borderRadius: BorderRadius.circular(4),
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
      LifecycleState.idle => const Color(0xFF616161),
      LifecycleState.preloading => const Color(0xFF00BCD4),
      LifecycleState.disposed => const Color(0xFF795548),
    };
  }
}

/// Small info badge (entry ID, cache status).
class _InfoBadge extends StatelessWidget {
  const _InfoBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Decorative social action button.
class _SocialButton extends StatelessWidget {
  const _SocialButton({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white, size: 28),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Progress bar driven by the adapter's [PlayerState] notifier.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.entry});

  final PoolEntry entry;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlayerState>(
      valueListenable: entry.adapter.stateNotifier,
      builder: (context, state, _) {
        final pos = state.position;
        final dur = state.duration;
        final progress =
            dur.inMilliseconds > 0 ? pos.inMilliseconds / dur.inMilliseconds : 0.0;

        return LinearProgressIndicator(
          value: progress.clamp(0.0, 1.0),
          minHeight: 2,
          backgroundColor: Colors.white24,
          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF7C4DFF)),
        );
      },
    );
  }
}
