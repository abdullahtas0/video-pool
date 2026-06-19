import 'device_capabilities.dart';
import 'device_status.dart';
import 'platform_interface.dart';

/// A [VideoPoolPlatform] implementation that does nothing.
///
/// Used on platforms where the native device-monitoring bridge is not
/// available (web, macOS, Windows, Linux). The core pooling logic is pure
/// Dart and the underlying player (e.g. media_kit) plays on these platforms,
/// so the pool runs normally — it simply forgoes native thermal/memory
/// throttling and system audio-focus management, which have no platform
/// channel implementation outside Android and iOS.
///
/// All methods return benign defaults: capabilities are reported as
/// unconstrained, monitoring is a no-op (no status events are emitted, so the
/// pool stays at its nominal thermal/memory state), and audio focus is always
/// treated as granted.
class NoOpVideoPoolPlatform implements VideoPoolPlatform {
  /// Creates a no-op platform.
  const NoOpVideoPoolPlatform();

  @override
  Future<DeviceCapabilities> getCapabilities() async {
    // Best-effort defaults. These platforms don't expose hardware decoder
    // counts via this plugin; values are intentionally permissive so they
    // never clamp the pool's configured concurrency.
    return const DeviceCapabilities(
      maxHardwareDecoders: 0,
      supportedCodecs: <String>[],
      totalMemoryBytes: 0,
    );
  }

  @override
  Future<void> startMonitoring() async {
    // No native monitoring on this platform.
  }

  @override
  Future<void> stopMonitoring() async {
    // No native monitoring on this platform.
  }

  @override
  Stream<DeviceStatus> get statusStream => const Stream<DeviceStatus>.empty();

  @override
  Future<bool> requestAudioFocus() async {
    // No system audio session to manage; treat focus as always granted so
    // playback proceeds normally.
    return true;
  }

  @override
  Future<void> releaseAudioFocus() async {
    // Nothing to release.
  }

  @override
  Stream<bool> get audioFocusStream => const Stream<bool>.empty();
}
