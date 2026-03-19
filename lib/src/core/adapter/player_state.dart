import 'package:flutter/foundation.dart';

import '../models/video_source.dart';

/// The phase of a player's playback lifecycle.
enum PlaybackPhase {
  /// Player is idle — no source loaded.
  idle,

  /// Player is preparing — loading source, allocating decoder.
  preparing,

  /// Player is ready — first frame decoded, waiting to play.
  ready,

  /// Player is actively playing video.
  playing,

  /// Player is paused — decoder still allocated for instant resume.
  paused,

  /// Player is rebuffering due to slow network.
  buffering,

  /// An error occurred during playback or preparation.
  error,

  /// Player has been disposed and cannot be reused.
  disposed,
}

/// Immutable snapshot of a player's current state.
///
/// Used with [ValueNotifier] to drive UI updates via [ValueListenableBuilder].
/// Use [copyWith] to derive a new state from an existing one.
@immutable
class PlayerState {
  /// Creates a new [PlayerState].
  const PlayerState({
    this.phase = PlaybackPhase.idle,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.bufferedFraction = 0.0,
    this.currentSource,
    this.errorMessage,
  }) : assert(
          bufferedFraction >= 0.0 && bufferedFraction <= 1.0,
          'bufferedFraction must be 0.0–1.0',
        );

  /// The current playback phase.
  final PlaybackPhase phase;

  /// Current playback position.
  final Duration position;

  /// Total duration of the loaded media.
  final Duration duration;

  /// Fraction of media that has been buffered, from 0.0 to 1.0.
  final double bufferedFraction;

  /// The video source currently loaded in this player, if any.
  final VideoSource? currentSource;

  /// Human-readable error message when [phase] is [PlaybackPhase.error].
  final String? errorMessage;

  /// Creates a copy of this [PlayerState] with the given fields replaced.
  ///
  /// To explicitly clear [currentSource] or [errorMessage], pass
  /// [clearCurrentSource] or [clearErrorMessage] as `true`.
  PlayerState copyWith({
    PlaybackPhase? phase,
    Duration? position,
    Duration? duration,
    double? bufferedFraction,
    VideoSource? currentSource,
    bool clearCurrentSource = false,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return PlayerState(
      phase: phase ?? this.phase,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      bufferedFraction: bufferedFraction ?? this.bufferedFraction,
      currentSource:
          clearCurrentSource ? null : (currentSource ?? this.currentSource),
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PlayerState &&
        other.phase == phase &&
        other.position == position &&
        other.duration == duration &&
        other.bufferedFraction == bufferedFraction &&
        other.currentSource == currentSource &&
        other.errorMessage == errorMessage;
  }

  @override
  int get hashCode => Object.hash(
        phase,
        position,
        duration,
        bufferedFraction,
        currentSource,
        errorMessage,
      );

  @override
  String toString() =>
      'PlayerState(phase: $phase, position: $position, duration: $duration)';
}
