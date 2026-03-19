import 'package:flutter/material.dart';

import '../core/models/playback_config.dart';
import '../core/models/video_source.dart';
import 'video_card.dart';
import 'video_pool_provider.dart';
import 'visibility_tracker.dart';

/// TikTok/Reels style full-screen vertical video feed.
///
/// Uses a [PageView.builder] for snapping full-screen video pages.
/// Integrates with [VisibilityTracker] to compute which page is primary
/// and calls [VideoPool.onVisibilityChanged] on page transitions.
///
/// Each page renders a [VideoCard] by default, or uses a custom
/// [itemBuilder] if provided.
class VideoFeedView extends StatefulWidget {
  /// Creates a [VideoFeedView].
  const VideoFeedView({
    super.key,
    required this.sources,
    this.playbackConfig,
    this.physics,
    this.itemBuilder,
    this.scrollDirection = Axis.vertical,
    this.initialPage = 0,
    this.onPageChanged,
  });

  /// The list of video sources to display.
  final List<VideoSource> sources;

  /// Optional playback configuration applied to all video cards.
  final PlaybackConfig? playbackConfig;

  /// Custom scroll physics for the page view.
  final ScrollPhysics? physics;

  /// Custom item builder. If null, a default [VideoCard] is used.
  ///
  /// The builder receives the build context, item index, and video source.
  final Widget Function(BuildContext, int, VideoSource)? itemBuilder;

  /// The scroll direction of the feed.
  final Axis scrollDirection;

  /// The initial page to display.
  final int initialPage;

  /// Called when the page changes.
  final ValueChanged<int>? onPageChanged;

  @override
  State<VideoFeedView> createState() => _VideoFeedViewState();
}

class _VideoFeedViewState extends State<VideoFeedView> {
  late PageController _controller;
  final VisibilityTracker _visibilityTracker = const VisibilityTracker();
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    _controller = PageController(initialPage: widget.initialPage);

    // Trigger initial visibility after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifyVisibility(_currentPage);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _notifyVisibility(int pageIndex) {
    final pool = VideoPoolProvider.maybeOf(context);
    if (pool == null) return;

    final update = _visibilityTracker.computePageVisibility(
      page: pageIndex.toDouble(),
      itemCount: widget.sources.length,
    );

    pool.onVisibilityChanged(
      primaryIndex: update.primaryIndex,
      visibilityRatios: update.visibilityRatios,
    );
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (_controller.hasClients && _controller.page != null) {
          final page = _controller.page!;
          final update = _visibilityTracker.computePageVisibility(
            page: page,
            itemCount: widget.sources.length,
          );

          // Only notify the pool if the primary page changed to avoid
          // excessive reconciliation calls during scroll animation.
          if (update.primaryIndex != _currentPage) {
            final pool = VideoPoolProvider.maybeOf(context);
            pool?.onVisibilityChanged(
              primaryIndex: update.primaryIndex,
              visibilityRatios: update.visibilityRatios,
            );
          }
        }
        return false;
      },
      child: PageView.builder(
        controller: _controller,
        scrollDirection: widget.scrollDirection,
        physics: widget.physics,
        itemCount: widget.sources.length,
        onPageChanged: (page) {
          _currentPage = page;
          _notifyVisibility(page);
          widget.onPageChanged?.call(page);
        },
        itemBuilder: (context, index) {
          if (widget.itemBuilder != null) {
            return widget.itemBuilder!(context, index, widget.sources[index]);
          }
          return VideoCard(
            index: index,
            source: widget.sources[index],
            playbackConfig: widget.playbackConfig,
          );
        },
      ),
    );
  }
}
