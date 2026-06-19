import 'package:flutter/foundation.dart';

import 'device_monitor.dart';
import 'noop_platform.dart';
import 'platform_interface.dart';

/// Returns the default [VideoPoolPlatform] for the current runtime platform.
///
/// The native device-monitoring bridge (thermal, memory, audio focus) is
/// implemented only for Android and iOS. On every other platform — web,
/// macOS, Windows, Linux — a [NoOpVideoPoolPlatform] is returned so the pool
/// runs without throwing `MissingPluginException`; it simply forgoes native
/// throttling and audio-focus management while the player still plays.
VideoPoolPlatform defaultVideoPoolPlatform() {
  if (kIsWeb) return const NoOpVideoPoolPlatform();
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return DeviceMonitor();
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
    case TargetPlatform.linux:
    case TargetPlatform.fuchsia:
      return const NoOpVideoPoolPlatform();
  }
}
