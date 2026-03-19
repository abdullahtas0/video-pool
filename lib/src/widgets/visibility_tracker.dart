import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Result of a visibility computation.
///
/// Contains the index of the most visible item and a map of all visible
/// items to their intersection ratios.
class VisibilityUpdate {
  /// Creates a [VisibilityUpdate].
  const VisibilityUpdate({
    required this.primaryIndex,
    required this.visibilityRatios,
  });

  /// The index of the most visible item (highest intersection ratio).
  final int primaryIndex;

  /// Map from item index to its visibility ratio (0.0–1.0).
  ///
  /// Only items with a positive intersection ratio are included.
  final Map<int, double> visibilityRatios;
}

/// Computes intersection ratios for items in a scrollable list.
///
/// Used by [VideoFeedView] and [VideoListView] to determine which video
/// items are visible and how much of each is on screen. The pool uses
/// these ratios to decide which videos to play, preload, or release.
class VisibilityTracker {
  /// Creates a [VisibilityTracker] with the given thresholds.
  ///
  /// [playThreshold] is the minimum visibility ratio to trigger auto-play.
  /// [pauseThreshold] is the visibility ratio below which to auto-pause.
  const VisibilityTracker({
    this.playThreshold = 0.6,
    this.pauseThreshold = 0.4,
  }) : assert(playThreshold > pauseThreshold,
            'playThreshold must be greater than pauseThreshold');

  /// Minimum visibility ratio (0.0–1.0) to trigger auto-play.
  final double playThreshold;

  /// Visibility ratio below which to auto-pause.
  final double pauseThreshold;

  /// Compute visibility ratios for items given a [ScrollNotification].
  ///
  /// [notification] is the scroll event from the framework.
  /// [itemCount] is the total number of items in the list.
  /// [itemExtent] is the size of each item along the scroll axis (in pixels).
  ///
  /// Returns a [VisibilityUpdate] containing the primary (most visible)
  /// index and all visibility ratios.
  VisibilityUpdate computeVisibility({
    required ScrollNotification notification,
    required int itemCount,
    required double itemExtent,
  }) {
    if (itemCount == 0 || itemExtent <= 0) {
      return const VisibilityUpdate(
        primaryIndex: -1,
        visibilityRatios: {},
      );
    }

    final metrics = notification.metrics;
    final viewportStart = metrics.pixels;
    final viewportEnd = viewportStart + metrics.viewportDimension;

    final ratios = <int, double>{};
    var bestIndex = -1;
    var bestRatio = 0.0;

    // Compute the range of items that could be visible.
    final firstPossible = math.max(0, (viewportStart / itemExtent).floor());
    final lastPossible =
        math.min(itemCount - 1, (viewportEnd / itemExtent).ceil());

    for (var i = firstPossible; i <= lastPossible; i++) {
      final itemStart = i * itemExtent;
      final itemEnd = itemStart + itemExtent;

      // Intersection of item with viewport.
      final visibleStart = math.max(viewportStart, itemStart);
      final visibleEnd = math.min(viewportEnd, itemEnd);
      final visibleLength = math.max(0.0, visibleEnd - visibleStart);

      final ratio = visibleLength / itemExtent;

      if (ratio > 0) {
        ratios[i] = ratio;
        if (ratio > bestRatio) {
          bestRatio = ratio;
          bestIndex = i;
        }
      }
    }

    return VisibilityUpdate(
      primaryIndex: bestIndex,
      visibilityRatios: ratios,
    );
  }

  /// Compute visibility for a [PageView]-style widget.
  ///
  /// [page] is the current fractional page from [PageController.page].
  /// [itemCount] is the total number of pages.
  ///
  /// In a [PageView] typically only one or two pages are visible.
  VisibilityUpdate computePageVisibility({
    required double page,
    required int itemCount,
  }) {
    if (itemCount == 0) {
      return const VisibilityUpdate(
        primaryIndex: -1,
        visibilityRatios: {},
      );
    }

    final currentPage = page.floor();
    final fraction = page - currentPage;

    final ratios = <int, double>{};

    if (currentPage >= 0 && currentPage < itemCount) {
      ratios[currentPage] = 1.0 - fraction;
    }

    final nextPage = currentPage + 1;
    if (nextPage < itemCount && fraction > 0) {
      ratios[nextPage] = fraction;
    }

    var bestIndex = currentPage;
    if (fraction > 0.5 && nextPage < itemCount) {
      bestIndex = nextPage;
    }

    return VisibilityUpdate(
      primaryIndex: bestIndex.clamp(0, itemCount - 1),
      visibilityRatios: ratios,
    );
  }
}
