import 'package:flutter/material.dart';

import 'video_pool_provider.dart';
import 'visibility_tracker.dart';

/// Instagram-style mixed content list with video support.
///
/// Uses a [ListView.builder] with a [NotificationListener] for scroll
/// events. Integrates [VisibilityTracker] to compute intersection ratios
/// and calls [VideoPool.onVisibilityChanged] as the user scrolls.
///
/// Unlike [VideoFeedView], this supports mixed content — use [VideoCard]
/// for video items and any widget for non-video items.
class VideoListView extends StatefulWidget {
  /// Creates a [VideoListView].
  const VideoListView({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.physics,
    this.controller,
    this.itemExtent,
    this.padding,
  });

  /// Total number of items in the list.
  final int itemCount;

  /// Builder for each item in the list.
  final Widget Function(BuildContext, int) itemBuilder;

  /// Custom scroll physics.
  final ScrollPhysics? physics;

  /// Optional scroll controller.
  final ScrollController? controller;

  /// Fixed item extent (height) for all items. Required for accurate
  /// visibility tracking.
  ///
  /// If null, defaults to the viewport height (assumes full-screen items).
  final double? itemExtent;

  /// Padding around the list.
  final EdgeInsetsGeometry? padding;

  @override
  State<VideoListView> createState() => _VideoListViewState();
}

class _VideoListViewState extends State<VideoListView> {
  final VisibilityTracker _visibilityTracker = const VisibilityTracker();

  @override
  void initState() {
    super.initState();
    // Trigger initial visibility after the first frame so the first
    // video starts playing, consistent with VideoFeedView behavior.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pool = VideoPoolProvider.maybeOf(context);
      pool?.onVisibilityChanged(
        primaryIndex: 0,
        visibilityRatios: const {0: 1.0},
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: ListView.builder(
        controller: widget.controller,
        physics: widget.physics,
        itemCount: widget.itemCount,
        itemExtent: widget.itemExtent,
        padding: widget.padding,
        itemBuilder: widget.itemBuilder,
      ),
    );
  }

  bool _onScroll(ScrollNotification notification) {
    final pool = VideoPoolProvider.maybeOf(context);
    if (pool == null) return false;

    final extent = widget.itemExtent ??
        notification.metrics.viewportDimension;

    final update = _visibilityTracker.computeVisibility(
      notification: notification,
      itemCount: widget.itemCount,
      itemExtent: extent,
    );

    if (update.primaryIndex >= 0) {
      pool.onVisibilityChanged(
        primaryIndex: update.primaryIndex,
        visibilityRatios: update.visibilityRatios,
      );
    }

    return false;
  }
}
