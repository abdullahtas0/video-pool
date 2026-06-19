import 'package:media_kit/media_kit.dart';

/// Applies libmpv network/HLS tuning to [player] (native platforms).
///
/// The dominant cost of starting an HLS stream is the chain of round-trips
/// (master playlist → media playlist → first segment) plus mpv probing every
/// variant to pick a bitrate. Starting at the lowest rendition lets the first
/// segment arrive fast; ABR then adapts upward during playback.
///
/// Best-effort: if the player's platform is not a [NativePlayer] (or a
/// property is unknown on this libmpv build), the call is silently ignored.
Future<void> applyNetworkTuning(Player player) async {
  final platform = player.platform;
  if (platform is! NativePlayer) return;
  try {
    // Begin at the lowest HLS variant so the first segment is small and
    // playback starts quickly. ABR still scales up during playback.
    await platform.setProperty('hls-bitrate', 'min');
    // Decode the first frame before filling a large read-ahead buffer.
    await platform.setProperty('cache', 'yes');
    await platform.setProperty('cache-secs', '10');
    await platform.setProperty('demuxer-readahead-secs', '5');
    // Fail fast on stalled segment requests instead of hanging the feed.
    await platform.setProperty('network-timeout', '10');
  } catch (_) {
    // Property unsupported on this platform/build — ignore.
  }
}
