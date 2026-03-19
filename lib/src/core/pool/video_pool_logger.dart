import 'dart:developer' as developer;

import 'pool_config.dart';

/// Logging utility for the video pool.
///
/// Messages are only emitted when the configured [level] is at least as
/// verbose as the message's level. All output is prefixed with `[VideoPool]`.
class VideoPoolLogger {
  /// Creates a [VideoPoolLogger] with the given verbosity [level].
  const VideoPoolLogger({this.level = LogLevel.none});

  /// The minimum verbosity level for messages to be emitted.
  final LogLevel level;

  /// Log a debug-level message.
  void debug(String message) {
    if (level.index >= LogLevel.debug.index) {
      developer.log('[VideoPool] $message', level: 500);
    }
  }

  /// Log an informational message.
  void info(String message) {
    if (level.index >= LogLevel.info.index) {
      developer.log('[VideoPool] $message', level: 800);
    }
  }

  /// Log a warning message.
  void warning(String message) {
    if (level.index >= LogLevel.warning.index) {
      developer.log('[VideoPool] WARNING: $message', level: 900);
    }
  }

  /// Log an error message with optional [error] and [stackTrace].
  void error(String message, [Object? error, StackTrace? stackTrace]) {
    if (level.index >= LogLevel.error.index) {
      developer.log(
        '[VideoPool] ERROR: $message',
        level: 1000,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
