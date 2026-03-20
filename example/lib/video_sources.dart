import 'package:video_pool/video_pool.dart';

/// Video sources for the Feed tab (TikTok/Reels style).
///
/// Mix of Google sample videos — short clips that load fast.
final feedVideos = [
  const VideoSource(
    url:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
    thumbnailUrl:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerBlazes.jpg',
    resolutionHint: ResolutionHint.hd720,
  ),
  const VideoSource(
    url:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4',
    thumbnailUrl:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerEscapes.jpg',
    resolutionHint: ResolutionHint.hd720,
  ),
  const VideoSource(
    url:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4',
    thumbnailUrl:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerFun.jpg',
    resolutionHint: ResolutionHint.hd720,
  ),
  const VideoSource(
    url:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyrides.mp4',
    thumbnailUrl:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerJoyrides.jpg',
    resolutionHint: ResolutionHint.hd720,
  ),
  const VideoSource(
    url:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4',
    thumbnailUrl:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerMeltdowns.jpg',
    resolutionHint: ResolutionHint.hd720,
  ),
  const VideoSource(
    url:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
    thumbnailUrl:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/BigBuckBunny.jpg',
    resolutionHint: ResolutionHint.hd720,
  ),
  const VideoSource(
    url:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
    thumbnailUrl:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ElephantsDream.jpg',
    resolutionHint: ResolutionHint.hd720,
  ),
  const VideoSource(
    url:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4',
    thumbnailUrl:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/Sintel.jpg',
    resolutionHint: ResolutionHint.hd720,
  ),
];

/// Video sources for the Discover tab (Instagram style).
///
/// Subset of feed videos used in the mixed content list.
final discoverVideos = [
  feedVideos[0],
  feedVideos[1],
  feedVideos[2],
  feedVideos[3],
  feedVideos[4],
];

/// Human-readable titles for each feed video.
const feedVideoTitles = [
  'For Bigger Blazes',
  'For Bigger Escapes',
  'For Bigger Fun',
  'For Bigger Joyrides',
  'For Bigger Meltdowns',
  'Big Buck Bunny',
  "Elephant's Dream",
  'Sintel',
];
