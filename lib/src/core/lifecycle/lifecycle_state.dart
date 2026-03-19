/// The lifecycle state of a video slot within the pool.
///
/// This is distinct from [PlaybackPhase] — it represents the orchestrator's
/// view of a slot, not the player's internal state. A slot transitions through
/// these states as the user scrolls and the orchestrator manages resources.
enum LifecycleState {
  /// Not in pool. Showing a static thumbnail placeholder.
  idle,

  /// Disk pre-fetch is in progress for this slot's video.
  preloading,

  /// A decoder has been allocated and is buffering the first frame.
  preparing,

  /// First frame is decoded and ready. Waiting for visibility to trigger play.
  ready,

  /// Active playback in progress.
  playing,

  /// Paused — decoder still allocated for instant resume via instance reuse.
  paused,

  /// Playing but rebuffering due to slow network conditions.
  buffering,

  /// An error occurred. Showing retry UI to the user.
  error,

  /// Player instance has been reclaimed (emergency memory pressure only).
  disposed,
}
