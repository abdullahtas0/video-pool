import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/adapter/player_adapter.dart';
import '../core/audio/audio_focus_manager.dart';
import '../core/models/video_source.dart';
import '../core/pool/pool_config.dart';
import '../core/pool/video_pool.dart';
import '../platform/device_monitor.dart';
import '../platform/device_status.dart';
import '../platform/platform_interface.dart';
import 'video_pool_provider.dart';

/// A [StatefulWidget] that owns the lifecycle of a [VideoPool].
///
/// Creates the pool on initialization and disposes it when the widget is
/// removed from the tree. Also manages [AudioFocusManager] and
/// [DeviceMonitor] integration.
///
/// Usage:
/// ```dart
/// VideoPoolScope(
///   config: const VideoPoolConfig(maxConcurrent: 3, preloadCount: 1),
///   adapterFactory: (id) => MediaKitAdapter(),
///   sourceResolver: (index) => videoSources[index],
///   child: VideoFeedView(sources: videoSources),
/// )
/// ```
class VideoPoolScope extends StatefulWidget {
  /// Creates a [VideoPoolScope].
  ///
  /// [config] controls pool sizing and behavior.
  /// [adapterFactory] is called to create each player adapter instance.
  /// [sourceResolver] maps video indices to their [VideoSource].
  /// [platform] is the platform interface for audio focus and device
  /// monitoring. Defaults to [DeviceMonitor] if not provided.
  const VideoPoolScope({
    super.key,
    required this.config,
    required this.adapterFactory,
    required this.sourceResolver,
    this.platform,
    required this.child,
  });

  /// Pool configuration.
  final VideoPoolConfig config;

  /// Factory to create player adapter instances.
  final PlayerAdapter Function(int id) adapterFactory;

  /// Resolves a video index to its [VideoSource].
  final VideoSourceResolver sourceResolver;

  /// Platform interface for audio focus and device monitoring.
  /// If null, a default [DeviceMonitor] is created.
  final VideoPoolPlatform? platform;

  /// The widget below this scope in the tree.
  final Widget child;

  @override
  State<VideoPoolScope> createState() => _VideoPoolScopeState();
}

class _VideoPoolScopeState extends State<VideoPoolScope>
    with WidgetsBindingObserver {
  late VideoPool _pool;
  late AudioFocusManager _audioFocusManager;
  late VideoPoolPlatform _platform;
  StreamSubscription<DeviceStatus>? _statusSubscription;

  @override
  void initState() {
    super.initState();

    _platform = widget.platform ?? DeviceMonitor();

    _pool = VideoPool(
      config: widget.config,
      adapterFactory: widget.adapterFactory,
      sourceResolver: widget.sourceResolver,
    );

    _audioFocusManager = AudioFocusManager(platform: _platform);
    _audioFocusManager.setCallbacks(
      onPause: _onShouldPause,
      onResume: _onShouldResume,
    );
    _audioFocusManager.startObserving();

    _startDeviceMonitoring();
  }

  Future<void> _startDeviceMonitoring() async {
    try {
      await _platform.startMonitoring();
      _statusSubscription = _platform.statusStream.listen(
        (status) {
          _pool.onDeviceStatusChanged(
            thermalLevel: status.thermalLevel,
            memoryPressure: status.memoryPressureLevel,
          );
        },
      );
    } catch (_) {
      // Platform monitoring may not be available (e.g. in tests).
    }
  }

  void _onShouldPause() {
    // Pause all playing entries by triggering a visibility change with no
    // visible items. This effectively pauses the current video.
    _pool.onVisibilityChanged(
      primaryIndex: -1,
      visibilityRatios: const {},
    );
  }

  void _onShouldResume() {
    // Resume is handled by the next scroll/visibility event, or the
    // feed widget can re-trigger visibility on app resume.
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _audioFocusManager.dispose();
    _pool.dispose();
    try {
      _platform.stopMonitoring();
    } catch (_) {
      // Ignore if monitoring was never started.
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VideoPoolProvider(
      pool: _pool,
      child: widget.child,
    );
  }
}
