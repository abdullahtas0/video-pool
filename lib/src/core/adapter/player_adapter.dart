import 'package:flutter/widgets.dart';

import '../models/video_source.dart';
import 'player_state.dart';

/// Abstract interface for a video player instance.
///
/// The adapter pattern decouples the pool from any specific player
/// implementation (e.g. media_kit, native AVPlayer, ExoPlayer).
///
/// The key method is [swapSource], which replaces the loaded media
/// **without** destroying the underlying decoder pipeline. This enables
/// instance reuse — the core optimization of the video pool.
abstract class PlayerAdapter {
  /// Swap media source while reusing the player wrapper and texture surface.
  ///
  /// This is the **key method** for instance reuse. The player wrapper and
  /// its associated texture surface are preserved, avoiding the cost of
  /// creating a new native player instance. The underlying decoder may be
  /// re-initialized depending on the player implementation, but the Flutter
  /// widget tree and texture registration remain stable.
  Future<void> swapSource(VideoSource source);

  /// Prepare for playback — buffer the first frame so it's ready instantly.
  Future<void> prepare();

  /// Start or resume playback.
  Future<void> play();

  /// Pause playback. The decoder remains allocated for instant resume.
  Future<void> pause();

  /// Fully dispose this player instance.
  ///
  /// **Only** called on pool shutdown or emergency memory pressure.
  /// During normal scrolling, players are reused via [swapSource] instead.
  Future<void> dispose();

  /// Whether this adapter is available for reuse (idle or paused, not playing).
  bool get isReusable;

  /// Notifier for the current player state.
  ///
  /// Listen to this with [ValueListenableBuilder] for reactive UI updates.
  ValueNotifier<PlayerState> get stateNotifier;

  /// Estimated memory usage of this player instance in bytes.
  ///
  /// Used by the pool to make eviction decisions under memory pressure.
  int get estimatedMemoryBytes;

  /// The widget that renders this player's video output.
  Widget get videoWidget;

  /// Current playback position.
  Duration get position;

  /// Total duration of the loaded media.
  Duration get duration;

  /// Seek to the given [position].
  Future<void> seekTo(Duration position);

  /// Set audio volume from 0.0 (silent) to 1.0 (full).
  Future<void> setVolume(double volume);

  /// Set playback speed from 0.5 to 2.0.
  Future<void> setSpeed(double speed);

  /// Set whether playback should loop.
  Future<void> setLooping(bool loop);
}
