/// Dart plugin registrant for desktop platforms (macOS, Windows, Linux).
///
/// video_pool needs no native platform channel on desktop — the device
/// monitor falls back to [NoOpVideoPoolPlatform] and the disk cache to its
/// native (`dart:io`) implementation, which already works on desktop. This
/// empty registrant exists only so the package can declare desktop support
/// in `pubspec.yaml` (and therefore advertise it on pub.dev).
class VideoPoolDesktopPlugin {
  /// Called automatically by Flutter's generated Dart plugin registrant.
  static void registerWith() {}
}
