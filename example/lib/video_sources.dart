import 'package:video_pool/video_pool.dart';

/// Video sources for the Feed tab (TikTok/Reels style).
///
/// Short, CORS-enabled CC0 sample clips that load quickly and play on every
/// platform (including web). Hosted on Flutter's own asset CDN and MDN.
const _bee =
    'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4';
const _butterfly =
    'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4';
const _flower =
    'https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4';

final feedVideos = [
  const VideoSource(url: _bee, resolutionHint: ResolutionHint.hd720),
  const VideoSource(url: _butterfly, resolutionHint: ResolutionHint.hd720),
  const VideoSource(url: _flower, resolutionHint: ResolutionHint.hd720),
  const VideoSource(url: _bee, resolutionHint: ResolutionHint.hd720),
  const VideoSource(url: _butterfly, resolutionHint: ResolutionHint.hd720),
  const VideoSource(url: _flower, resolutionHint: ResolutionHint.hd720),
  const VideoSource(url: _bee, resolutionHint: ResolutionHint.hd720),
  const VideoSource(url: _butterfly, resolutionHint: ResolutionHint.hd720),
];

/// Video sources for the Discover tab (Instagram style).
final discoverVideos = [
  feedVideos[0],
  feedVideos[1],
  feedVideos[2],
  feedVideos[3],
  feedVideos[4],
];

/// Human-readable titles for each feed video.
const feedVideoTitles = [
  'Bee',
  'Butterfly',
  'Flower',
  'Bee',
  'Butterfly',
  'Flower',
  'Bee',
  'Butterfly',
];
