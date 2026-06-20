import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// Web plugin registrant.
///
/// video_pool needs no web platform channel — pooling is pure Dart and
/// playback is handled by the chosen player (media_kit or video_player), while
/// the device monitor and disk cache fall back to no-op web stubs. This
/// registrant exists only so the package can declare web support.
class VideoPoolWebPlugin {
  /// Called automatically by Flutter's generated web plugin registrant.
  static void registerWith(Registrar registrar) {}
}
