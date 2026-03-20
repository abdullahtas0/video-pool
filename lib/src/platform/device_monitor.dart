import 'dart:async';

import 'package:flutter/services.dart';

import 'device_capabilities.dart';
import 'device_status.dart';
import 'platform_interface.dart';

/// Default [VideoPoolPlatform] implementation backed by platform channels.
///
/// Uses a [MethodChannel] for request/response calls (capabilities, start/stop,
/// audio focus) and an [EventChannel] for streaming device status updates from
/// the native layer.
class DeviceMonitor implements VideoPoolPlatform {
  /// Creates a [DeviceMonitor] with the default platform channels.
  DeviceMonitor() {
    _methodChannel.setMethodCallHandler(_handleMethodCall);
  }

  /// Method channel for one-shot calls to the native layer.
  static const MethodChannel _methodChannel =
      MethodChannel('dev.video_pool/device_monitor');

  /// Event channel for streaming device status updates.
  static const EventChannel _eventChannel =
      EventChannel('dev.video_pool/device_status');

  /// Cached broadcast stream from the event channel.
  Stream<DeviceStatus>? _statusStream;

  /// Controller for audio focus change events from native side.
  final StreamController<bool> _audioFocusController =
      StreamController<bool>.broadcast();

  @override
  Future<DeviceCapabilities> getCapabilities() async {
    final result =
        await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
      'getCapabilities',
    );
    if (result == null) {
      return const DeviceCapabilities(
        maxHardwareDecoders: 0,
        supportedCodecs: [],
        totalMemoryBytes: 0,
      );
    }
    return DeviceCapabilities.fromMap(Map<String, dynamic>.from(result));
  }

  @override
  Future<void> startMonitoring() async {
    await _methodChannel.invokeMethod<void>('startMonitoring');
  }

  @override
  Future<void> stopMonitoring() async {
    await _methodChannel.invokeMethod<void>('stopMonitoring');
  }

  @override
  Stream<DeviceStatus> get statusStream {
    _statusStream ??= _eventChannel
        .receiveBroadcastStream()
        .map<DeviceStatus>((dynamic event) {
      return DeviceStatus.fromMap(Map<String, dynamic>.from(
        event as Map<dynamic, dynamic>,
      ));
    });
    return _statusStream!;
  }

  @override
  Future<bool> requestAudioFocus() async {
    final result = await _methodChannel.invokeMethod<bool>('requestAudioFocus');
    return result ?? false;
  }

  @override
  Future<void> releaseAudioFocus() async {
    await _methodChannel.invokeMethod<void>('releaseAudioFocus');
  }

  @override
  Stream<bool> get audioFocusStream => _audioFocusController.stream;

  /// Handles method calls from the native side (e.g. audio focus changes).
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onAudioFocusChange':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final status = args['status'] as String;
        _audioFocusController.add(status == 'gained');
      default:
        break;
    }
  }
}
