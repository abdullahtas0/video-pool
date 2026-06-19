import 'package:media_kit/media_kit.dart';

/// Web no-op for network/HLS tuning.
///
/// media_kit's web player is not backed by libmpv, so there is no
/// `NativePlayer.setProperty` to call. HLS variant selection and buffering
/// are handled by the browser's media stack instead.
Future<void> applyNetworkTuning(Player player) async {
  // Nothing to tune on web.
}
