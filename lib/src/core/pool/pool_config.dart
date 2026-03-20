import 'package:flutter/foundation.dart';

import '../lifecycle/lifecycle_policy.dart';
import '../models/playback_config.dart';

/// Log verbosity level for [VideoPoolLogger].
enum LogLevel {
  /// No logging output.
  none,

  /// Only errors.
  error,

  /// Errors and warnings.
  warning,

  /// Errors, warnings, and informational messages.
  info,

  /// All messages including debug traces.
  debug,
}

/// Configuration for a [VideoPool] instance.
///
/// All fields have sensible defaults optimized for feed-style video playback.
/// This is an immutable value object — use [copyWith] to derive variations.
@immutable
class VideoPoolConfig {
  /// Creates a [VideoPoolConfig] with sensible defaults.
  ///
  /// - [maxConcurrent] controls how many players can be active at once.
  /// - [preloadCount] controls how many adjacent slots to preload.
  /// - [memoryBudgetBytes] is the soft memory budget for all players combined.
  /// - [visibilityPlayThreshold] is the minimum visibility to auto-play.
  /// - [visibilityPauseThreshold] is the visibility below which to auto-pause.
  /// - [preloadTimeout] is how long to wait for a preload before giving up.
  const VideoPoolConfig({
    this.maxConcurrent = 3,
    this.preloadCount = 1,
    this.memoryBudgetBytes = 150 * 1024 * 1024, // 150 MB
    this.visibilityPlayThreshold = 0.6,
    this.visibilityPauseThreshold = 0.4,
    this.preloadTimeout = const Duration(seconds: 10),
    this.defaultPlaybackConfig = const PlaybackConfig(),
    this.lifecyclePolicy,
    this.logLevel = LogLevel.none,
  })  : assert(maxConcurrent > 0, 'maxConcurrent must be positive'),
        assert(maxConcurrent <= 10, 'maxConcurrent must not exceed 10'),
        assert(preloadCount >= 0, 'preloadCount must be non-negative'),
        assert(
          preloadCount < maxConcurrent,
          'preloadCount must be less than maxConcurrent '
              '(at least 1 slot is needed for the primary player)',
        ),
        assert(memoryBudgetBytes > 0, 'memoryBudgetBytes must be positive'),
        assert(
          visibilityPlayThreshold > visibilityPauseThreshold,
          'playThreshold must be greater than pauseThreshold',
        ),
        assert(
          visibilityPlayThreshold >= 0.0 && visibilityPlayThreshold <= 1.0,
          'visibilityPlayThreshold must be 0.0–1.0',
        ),
        assert(
          visibilityPauseThreshold >= 0.0 && visibilityPauseThreshold <= 1.0,
          'visibilityPauseThreshold must be 0.0–1.0',
        );

  /// Maximum number of player instances that can be active simultaneously.
  final int maxConcurrent;

  /// Number of adjacent slots to preload ahead of the current position.
  final int preloadCount;

  /// Soft memory budget in bytes for all pooled players combined.
  final int memoryBudgetBytes;

  /// Minimum visibility fraction (0.0–1.0) to trigger auto-play.
  final double visibilityPlayThreshold;

  /// Visibility fraction below which to auto-pause.
  final double visibilityPauseThreshold;

  /// Maximum time to wait for a preload operation to complete.
  final Duration preloadTimeout;

  /// Default playback configuration applied to all new players.
  final PlaybackConfig defaultPlaybackConfig;

  /// Custom lifecycle policy. When null, [DefaultLifecyclePolicy] is used.
  final LifecyclePolicy? lifecyclePolicy;

  /// Log verbosity level.
  final LogLevel logLevel;

  /// Creates a copy with the given fields replaced.
  VideoPoolConfig copyWith({
    int? maxConcurrent,
    int? preloadCount,
    int? memoryBudgetBytes,
    double? visibilityPlayThreshold,
    double? visibilityPauseThreshold,
    Duration? preloadTimeout,
    PlaybackConfig? defaultPlaybackConfig,
    LifecyclePolicy? lifecyclePolicy,
    LogLevel? logLevel,
  }) {
    return VideoPoolConfig(
      maxConcurrent: maxConcurrent ?? this.maxConcurrent,
      preloadCount: preloadCount ?? this.preloadCount,
      memoryBudgetBytes: memoryBudgetBytes ?? this.memoryBudgetBytes,
      visibilityPlayThreshold:
          visibilityPlayThreshold ?? this.visibilityPlayThreshold,
      visibilityPauseThreshold:
          visibilityPauseThreshold ?? this.visibilityPauseThreshold,
      preloadTimeout: preloadTimeout ?? this.preloadTimeout,
      defaultPlaybackConfig:
          defaultPlaybackConfig ?? this.defaultPlaybackConfig,
      lifecyclePolicy: lifecyclePolicy ?? this.lifecyclePolicy,
      logLevel: logLevel ?? this.logLevel,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VideoPoolConfig &&
        other.maxConcurrent == maxConcurrent &&
        other.preloadCount == preloadCount &&
        other.memoryBudgetBytes == memoryBudgetBytes &&
        other.visibilityPlayThreshold == visibilityPlayThreshold &&
        other.visibilityPauseThreshold == visibilityPauseThreshold &&
        other.preloadTimeout == preloadTimeout &&
        other.defaultPlaybackConfig == defaultPlaybackConfig &&
        other.logLevel == logLevel;
  }

  @override
  int get hashCode => Object.hash(
        maxConcurrent,
        preloadCount,
        memoryBudgetBytes,
        visibilityPlayThreshold,
        visibilityPauseThreshold,
        preloadTimeout,
        defaultPlaybackConfig,
        logLevel,
      );

  @override
  String toString() => 'VideoPoolConfig('
      'maxConcurrent: $maxConcurrent, '
      'preloadCount: $preloadCount, '
      'memoryBudget: ${memoryBudgetBytes ~/ (1024 * 1024)}MB)';
}
