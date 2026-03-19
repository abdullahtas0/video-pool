import 'package:flutter/material.dart';

import '../core/lifecycle/lifecycle_state.dart';
import '../core/models/playback_config.dart';
import '../core/models/video_source.dart';
import '../core/pool/pool_entry.dart';
import 'video_error_widget.dart';
import 'video_overlay.dart';
import 'video_pool_provider.dart';
import 'video_thumbnail.dart';

/// Individual video widget with full lifecycle management.
///
/// Listens to the [PoolEntry.lifecycleNotifier] for its assigned index
/// and renders the appropriate UI state:
///
/// - idle/preloading/disposed: [VideoThumbnail]
/// - preparing: [VideoThumbnail] with loading spinner
/// - ready: adapter's video widget (hidden behind thumbnail until play)
/// - playing: adapter's video widget with optional overlay
/// - paused: adapter's video widget with pause overlay
/// - buffering: adapter's video widget with buffering overlay
/// - error: [VideoErrorWidget]
class VideoCard extends StatefulWidget {
  /// Creates a [VideoCard].
  const VideoCard({
    super.key,
    required this.index,
    required this.source,
    this.playbackConfig,
    this.thumbnail,
    this.errorWidget,
    this.showOverlay = true,
  });

  /// The index of this video in the feed/list.
  final int index;

  /// The video source for this card.
  final VideoSource source;

  /// Optional playback configuration override.
  final PlaybackConfig? playbackConfig;

  /// Custom thumbnail widget. If null, [VideoThumbnail] is used with
  /// the source's [VideoSource.thumbnailUrl].
  final Widget? thumbnail;

  /// Custom error widget. If null, [VideoErrorWidget] is used.
  final Widget? errorWidget;

  /// Whether to show the play/pause overlay controls.
  final bool showOverlay;

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  @override
  Widget build(BuildContext context) {
    final pool = VideoPoolProvider.of(context);
    final entry = pool.getEntryForIndex(widget.index);

    if (entry == null) {
      // No pool entry assigned to this index — show thumbnail.
      return _buildThumbnail();
    }

    return ValueListenableBuilder<LifecycleState>(
      valueListenable: entry.lifecycleNotifier,
      builder: (context, lifecycleState, _) {
        return _buildForState(lifecycleState, entry);
      },
    );
  }

  Widget _buildForState(LifecycleState state, PoolEntry entry) {
    switch (state) {
      case LifecycleState.idle:
      case LifecycleState.preloading:
      case LifecycleState.disposed:
        return _buildThumbnail();

      case LifecycleState.preparing:
        return Stack(
          fit: StackFit.expand,
          children: [
            _buildThumbnail(),
            const Center(
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3.0,
              ),
            ),
          ],
        );

      case LifecycleState.ready:
        return Stack(
          fit: StackFit.expand,
          children: [
            entry.adapter.videoWidget,
            _buildThumbnail(),
          ],
        );

      case LifecycleState.playing:
        return Stack(
          fit: StackFit.expand,
          children: [
            entry.adapter.videoWidget,
            if (widget.showOverlay)
              VideoOverlay(
                lifecycleState: state,
                onTap: () => _togglePlayPause(entry),
              ),
          ],
        );

      case LifecycleState.paused:
        return Stack(
          fit: StackFit.expand,
          children: [
            entry.adapter.videoWidget,
            if (widget.showOverlay)
              VideoOverlay(
                lifecycleState: state,
                onTap: () => _togglePlayPause(entry),
              ),
          ],
        );

      case LifecycleState.buffering:
        return Stack(
          fit: StackFit.expand,
          children: [
            entry.adapter.videoWidget,
            if (widget.showOverlay)
              VideoOverlay(
                lifecycleState: state,
              ),
          ],
        );

      case LifecycleState.error:
        return widget.errorWidget ??
            VideoErrorWidget(
              onRetry: () => _retry(entry),
            );
    }
  }

  Widget _buildThumbnail() {
    return widget.thumbnail ??
        VideoThumbnail(
          thumbnailUrl: widget.source.thumbnailUrl,
        );
  }

  void _togglePlayPause(PoolEntry entry) {
    // Route through the pool so internal state tracking stays consistent.
    final pool = VideoPoolProvider.of(context);
    pool.togglePlayPause(widget.index);
  }

  void _retry(PoolEntry entry) {
    final pool = VideoPoolProvider.of(context);
    // Re-trigger visibility to let the pool reassign and retry.
    pool.onVisibilityChanged(
      primaryIndex: widget.index,
      visibilityRatios: {widget.index: 1.0},
    );
  }
}
