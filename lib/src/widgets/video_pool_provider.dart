import 'package:flutter/widgets.dart';

import '../core/pool/video_pool.dart';

/// An [InheritedWidget] that exposes a [VideoPool] to the widget tree.
///
/// Place a [VideoPoolProvider] above any widgets that need access to the
/// pool. Retrieve the pool via [VideoPoolProvider.of] or
/// [VideoPoolProvider.maybeOf].
///
/// Typically you don't use this directly — [VideoPoolScope] creates it
/// automatically. Use this only if you need manual control over pool
/// lifecycle.
class VideoPoolProvider extends InheritedWidget {
  /// Creates a [VideoPoolProvider] exposing [pool] to descendants.
  const VideoPoolProvider({
    super.key,
    required this.pool,
    required super.child,
  });

  /// The [VideoPool] instance available to descendants.
  final VideoPool pool;

  /// Returns the nearest [VideoPool] from the widget tree.
  ///
  /// Throws a [FlutterError] if no [VideoPoolProvider] is found above
  /// the given [context].
  static VideoPool of(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<VideoPoolProvider>();
    if (provider == null) {
      throw FlutterError(
        'VideoPoolProvider.of() called with a context that does not '
        'contain a VideoPoolProvider.\n'
        'No VideoPoolProvider ancestor could be found starting from the '
        'context that was passed to VideoPoolProvider.of(). This usually '
        'means that the widget tree does not include a VideoPoolScope.\n'
        'The context used was:\n'
        '  $context',
      );
    }
    return provider.pool;
  }

  /// Returns the nearest [VideoPool] from the widget tree, or null.
  static VideoPool? maybeOf(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<VideoPoolProvider>();
    return provider?.pool;
  }

  @override
  bool updateShouldNotify(VideoPoolProvider oldWidget) {
    return pool != oldWidget.pool;
  }
}
