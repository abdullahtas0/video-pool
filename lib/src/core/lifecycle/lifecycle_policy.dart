import 'package:flutter/foundation.dart';

/// The result of a lifecycle reconciliation pass.
///
/// Tells the orchestrator exactly which slot indices to play, pause,
/// preload, or release based on current visibility and device conditions.
@immutable
class ReconciliationPlan {
  /// Creates a new [ReconciliationPlan].
  const ReconciliationPlan({
    this.toRelease = const {},
    this.toPreload = const {},
    this.toPlay = const {},
    this.toPause = const {},
  });

  /// Indices whose player instances should be released back to the pool.
  final Set<int> toRelease;

  /// Indices that should begin preloading (disk fetch + first frame).
  final Set<int> toPreload;

  /// Indices that should start or continue playing (usually just one).
  final Set<int> toPlay;

  /// Indices that should be paused (visible but not primary).
  final Set<int> toPause;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReconciliationPlan &&
        setEquals(other.toRelease, toRelease) &&
        setEquals(other.toPreload, toPreload) &&
        setEquals(other.toPlay, toPlay) &&
        setEquals(other.toPause, toPause);
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAllUnordered(toRelease),
        Object.hashAllUnordered(toPreload),
        Object.hashAllUnordered(toPlay),
        Object.hashAllUnordered(toPause),
      );

  @override
  String toString() => 'ReconciliationPlan('
      'toRelease: $toRelease, '
      'toPreload: $toPreload, '
      'toPlay: $toPlay, '
      'toPause: $toPause)';
}

/// Strategy interface for lifecycle reconciliation logic.
///
/// The orchestrator calls [reconcile] on every visibility change or device
/// status update. Advanced users can provide a custom implementation to
/// change how players are allocated across visible slots.
abstract class LifecyclePolicy {
  /// Evaluate current state and produce a plan of actions.
  ///
  /// - [primaryIndex]: the slot index that is most visible / focused.
  /// - [visibilityRatios]: map of slot index to visibility fraction (0.0–1.0).
  /// - [effectiveMaxConcurrent]: max players that can be active simultaneously
  ///   (already adjusted for thermal/memory conditions).
  /// - [effectivePreloadCount]: how many adjacent slots to preload
  ///   (already adjusted for thermal/memory conditions).
  /// - [currentlyActive]: set of slot indices that currently have a player.
  ReconciliationPlan reconcile({
    required int primaryIndex,
    required Map<int, double> visibilityRatios,
    required int effectiveMaxConcurrent,
    required int effectivePreloadCount,
    required Set<int> currentlyActive,
  });
}

/// Default lifecycle policy for feed-style video playback.
///
/// Strategy:
/// - Play only the primary (most visible) index.
/// - Preload adjacent indices up to [effectivePreloadCount].
/// - Pause visible-but-not-primary indices.
/// - Release anything beyond [effectiveMaxConcurrent].
class DefaultLifecyclePolicy implements LifecyclePolicy {
  /// Creates a [DefaultLifecyclePolicy].
  const DefaultLifecyclePolicy();

  @override
  ReconciliationPlan reconcile({
    required int primaryIndex,
    required Map<int, double> visibilityRatios,
    required int effectiveMaxConcurrent,
    required int effectivePreloadCount,
    required Set<int> currentlyActive,
  }) {
    final toPlay = <int>{primaryIndex};
    final toPause = <int>{};
    final toPreload = <int>{};
    final toRelease = <int>{};

    // Determine preload window around the primary index.
    for (var offset = 1; offset <= effectivePreloadCount; offset++) {
      toPreload.add(primaryIndex + offset);
      toPreload.add(primaryIndex - offset);
    }
    // Don't preload negative indices.
    toPreload.removeWhere((index) => index < 0);
    // Don't preload the primary — it will be played.
    toPreload.remove(primaryIndex);

    // Pause visible slots that aren't primary or preloading.
    for (final entry in visibilityRatios.entries) {
      final index = entry.key;
      if (index != primaryIndex &&
          !toPreload.contains(index) &&
          entry.value > 0.0) {
        toPause.add(index);
      }
    }

    // Previously active entries that are now in the preload set (but not
    // primary) must be paused to stop their audio playback. Without this,
    // an entry that was playing keeps its audio running when it transitions
    // from primary to preloaded on scroll.
    for (final index in currentlyActive) {
      if (toPreload.contains(index) && index != primaryIndex) {
        toPause.add(index);
      }
    }

    // The desired active set is play + preload + pause.
    final desiredActive = {...toPlay, ...toPreload, ...toPause};

    // Release any currently active slots that aren't in the desired set,
    // or trim to stay within the concurrency limit.
    final activeOverflow = <int>{};
    for (final index in currentlyActive) {
      if (!desiredActive.contains(index)) {
        activeOverflow.add(index);
      }
    }
    toRelease.addAll(activeOverflow);

    // If we still exceed the concurrency limit, release the furthest slots.
    final totalDesired = desiredActive.length;
    if (totalDesired > effectiveMaxConcurrent) {
      // Sort desired by distance from primary, release the furthest.
      final sorted = desiredActive.toList()
        ..sort((a, b) =>
            (a - primaryIndex).abs().compareTo((b - primaryIndex).abs()));

      for (var i = effectiveMaxConcurrent; i < sorted.length; i++) {
        final index = sorted[i];
        toRelease.add(index);
        toPreload.remove(index);
        toPause.remove(index);
      }
    }

    return ReconciliationPlan(
      toRelease: toRelease,
      toPreload: toPreload,
      toPlay: toPlay,
      toPause: toPause,
    );
  }
}
