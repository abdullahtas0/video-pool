import 'device_capabilities.dart';
import 'device_status.dart';

/// Abstract interface for native device monitoring.
///
/// Provides access to hardware capabilities, thermal/memory status streams,
/// and system audio focus management. Implementations use platform channels
/// to communicate with iOS (Swift) and Android (Kotlin) native code.
abstract class VideoPoolPlatform {
  /// Queries device hardware capabilities (one-time call).
  ///
  /// Returns information about hardware decoder count, supported codecs,
  /// and total memory which the pool manager uses to set initial limits.
  Future<DeviceCapabilities> getCapabilities();

  /// Starts periodic monitoring of device status (thermal, memory, battery).
  ///
  /// After calling this, events will be delivered via [statusStream].
  Future<void> startMonitoring();

  /// Stops monitoring. No further events will be emitted on [statusStream].
  Future<void> stopMonitoring();

  /// Stream of device status updates emitted while monitoring is active.
  ///
  /// Each event contains the latest thermal level, available memory,
  /// memory pressure classification, battery level, and low-power mode flag.
  Stream<DeviceStatus> get statusStream;

  /// Requests system audio focus for video playback.
  ///
  /// On iOS this configures `AVAudioSession` for playback.
  /// On Android this calls `AudioManager.requestAudioFocus`.
  /// Returns `true` if focus was granted.
  Future<bool> requestAudioFocus();

  /// Releases system audio focus previously acquired via [requestAudioFocus].
  Future<void> releaseAudioFocus();

  /// Stream of audio focus changes from the system.
  ///
  /// Emits `true` when audio focus is gained, `false` when lost.
  /// Default implementation returns an empty stream.
  Stream<bool> get audioFocusStream => const Stream.empty();
}
