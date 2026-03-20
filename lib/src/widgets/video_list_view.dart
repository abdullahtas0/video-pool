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
  int _lastPrimaryIndex = -1;
  int _lastVisibleCount = 0;
  double _dragStartPosition = 0.0;
  DateTime _dragStartTime = DateTime.now();
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    // Trigger initial visibility after the first frame so the first
    // video starts playing, consistent with VideoFeedView behavior.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Trigger initial visibility with the first few visible indices.
      // This ensures the pool can find a video source even if the first
      // item is non-video content (e.g. text post in a mixed feed).
      final pool = VideoPoolProvider.maybeOf(context);
      if (pool == null) return;
      final visibleCount = widget.itemExtent != null
          ? (MediaQuery.of(context).size.height / widget.itemExtent!).ceil()
          : 3;
      final ratios = <int, double>{};
      for (var i = 0; i < visibleCount && i < widget.itemCount; i++) {
        ratios[i] = i == 0 ? 1.0 : 0.5;
      }
      pool.onVisibilityChanged(
        primaryIndex: 0,
        visibilityRatios: ratios,
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
      // Coarse filter: only notify if primary or visible count changed.
      // Fine-grained ratio filtering is handled by pool-level threshold
      // state machine (VideoPool.onVisibilityChanged).
      if (update.primaryIndex != _lastPrimaryIndex ||
          update.visibilityRatios.length != _lastVisibleCount) {
        _lastPrimaryIndex = update.primaryIndex;
        _lastVisibleCount = update.visibilityRatios.length;
        pool.onVisibilityChanged(
          primaryIndex: update.primaryIndex,
          visibilityRatios: update.visibilityRatios,
        );
      }
    }

    // Track drag for velocity estimation (prediction engine).
    if (notification is ScrollStartNotification) {
      _isDragging = notification.dragDetails != null;
      _dragStartPosition = notification.metrics.pixels;
      _dragStartTime = DateTime.now();
    } else if (notification is ScrollEndNotification && _isDragging) {
      final dt = DateTime.now().difference(_dragStartTime).inMilliseconds;
      if (dt > 0) {
        final velocity = (notification.metrics.pixels - _dragStartPosition) /
            dt * 1000;
        if (velocity.abs() > 0) {
          pool.onScrollUpdate(
            position: notification.metrics.pixels,
            velocity: velocity,
            itemExtent: extent,
            itemCount: widget.itemCount,
          );
        }
      }
      _isDragging = false;
    }

    return false;
  }
}
