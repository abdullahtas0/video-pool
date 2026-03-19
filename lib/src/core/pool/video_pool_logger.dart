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
      // ignore: avoid_print
      print('[VideoPool] $message');
    }
  }

  /// Log an informational message.
  void info(String message) {
    if (level.index >= LogLevel.info.index) {
      // ignore: avoid_print
      print('[VideoPool] $message');
    }
  }

  /// Log a warning message.
  void warning(String message) {
    if (level.index >= LogLevel.warning.index) {
      // ignore: avoid_print
      print('[VideoPool] WARNING: $message');
    }
  }

  /// Log an error message with optional [error] and [stackTrace].
  void error(String message, [Object? error, StackTrace? stackTrace]) {
    if (level.index >= LogLevel.error.index) {
      // ignore: avoid_print
      print('[VideoPool] ERROR: $message${error != null ? ' $error' : ''}');
    }
  }
}
