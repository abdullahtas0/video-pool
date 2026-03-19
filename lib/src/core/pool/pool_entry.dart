import 'package:flutter/widgets.dart';

import '../adapter/player_adapter.dart';
import '../lifecycle/lifecycle_state.dart';
import '../models/video_source.dart';

/// Wraps a single pooled [PlayerAdapter] with lifecycle metadata.
///
/// Each [PoolEntry] tracks which video index (if any) the adapter is
/// currently assigned to, and when it was last used (for LRU eviction).
class PoolEntry {
  /// Creates a [PoolEntry] wrapping the given [adapter].
  PoolEntry({
    required this.id,
    required this.adapter,
  })  : lifecycleNotifier = ValueNotifier<LifecycleState>(LifecycleState.idle),
        lastUsed = DateTime.now();

  /// Unique identifier for this pool entry.
  final int id;

  /// The underlying player adapter.
  final PlayerAdapter adapter;

  /// Notifier for the orchestrator's view of this entry's lifecycle.
  final ValueNotifier<LifecycleState> lifecycleNotifier;

  /// The video source currently loaded in this entry, if any.
  VideoSource? currentSource;

  /// When this entry was last used (for LRU eviction ordering).
  DateTime lastUsed;

  /// Which video index this entry is assigned to, or null if idle.
  int? assignedIndex;

  /// The current lifecycle state of this entry.
  LifecycleState get lifecycleState => lifecycleNotifier.value;

  /// Whether this entry is idle (not assigned to any index).
  bool get isIdle => assignedIndex == null;

  /// Whether this entry is assigned to the given [index].
  bool isAssignedTo(int index) => assignedIndex == index;

  /// Assign this entry to a video [index] with the given [source].
  ///
  /// Updates [assignedIndex], [currentSource], and [lastUsed].
  void assignTo(int index, VideoSource source) {
    assignedIndex = index;
    currentSource = source;
    lastUsed = DateTime.now();
  }

  /// Release this entry back to the idle pool.
  ///
  /// Clears the assignment but does NOT dispose the adapter.
  void release() {
    assignedIndex = null;
    currentSource = null;
    lifecycleNotifier.value = LifecycleState.idle;
  }

  /// Dispose of the lifecycle notifier.
  ///
  /// Call this only when the entry is being permanently removed from the pool.
  void disposeNotifier() {
    lifecycleNotifier.dispose();
  }
}
