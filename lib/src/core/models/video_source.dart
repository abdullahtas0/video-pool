import 'package:flutter/foundation.dart';

/// Hint about expected video resolution for memory estimation.
enum ResolutionHint {
  /// 720p (1280x720) — ~12 MB estimated memory per player.
  hd720,

  /// 1080p (1920x1080) — ~24 MB estimated memory per player.
  hd1080,

  /// 4K UHD (3840x2160) — ~96 MB estimated memory per player.
  uhd4k,
}

/// The type of video source.
enum VideoSourceType {
  /// A remote video accessible via HTTP/HTTPS.
  network,

  /// A local file on the device filesystem.
  file,

  /// A bundled asset within the Flutter app.
  asset,
}

/// Describes a video resource to be played.
///
/// [VideoSource] is an immutable value object that encapsulates everything
/// needed to locate and load a video. The [cacheKey] defaults to [url] when
/// not explicitly provided, which is correct for most use cases.
@immutable
class VideoSource {
  /// Creates a new [VideoSource].
  ///
  /// [url] is required and must point to the video resource.
  /// [cacheKey] defaults to [url] if not provided.
  const VideoSource({
    required this.url,
    this.headers = const {},
    String? cacheKey,
    this.thumbnailUrl,
    this.type = VideoSourceType.network,
    this.resolutionHint,
  }) : cacheKey = cacheKey ?? url;

  /// The URL or path of the video resource.
  final String url;

  /// Optional HTTP headers for network requests (e.g. authorization).
  final Map<String, String> headers;

  /// Key used for disk caching. Defaults to [url].
  final String cacheKey;

  /// Optional thumbnail URL shown before playback begins.
  final String? thumbnailUrl;

  /// The type of this video source.
  final VideoSourceType type;

  /// Optional hint about expected resolution for memory estimation.
  final ResolutionHint? resolutionHint;

  /// Estimated memory usage in bytes based on [resolutionHint].
  ///
  /// Returns null if no hint is set (adapter will use its own estimate).
  /// Calculation: width * height * 4 bytes (RGBA) * 3 frame buffers.
  int? get estimatedMemoryBytes {
    if (resolutionHint == null) return null;
    return switch (resolutionHint!) {
      ResolutionHint.hd720 => 1280 * 720 * 4 * 3,     // ~11 MB
      ResolutionHint.hd1080 => 1920 * 1080 * 4 * 3,   // ~24 MB
      ResolutionHint.uhd4k => 3840 * 2160 * 4 * 3,    // ~95 MB
    };
  }

  /// Creates a copy of this [VideoSource] with the given fields replaced.
  VideoSource copyWith({
    String? url,
    Map<String, String>? headers,
    String? cacheKey,
    String? thumbnailUrl,
    VideoSourceType? type,
    ResolutionHint? resolutionHint,
  }) {
    return VideoSource(
      url: url ?? this.url,
      headers: headers ?? this.headers,
      cacheKey: cacheKey ?? this.cacheKey,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      type: type ?? this.type,
      resolutionHint: resolutionHint ?? this.resolutionHint,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VideoSource &&
        other.url == url &&
        mapEquals(other.headers, headers) &&
        other.cacheKey == cacheKey &&
        other.thumbnailUrl == thumbnailUrl &&
        other.type == type &&
        other.resolutionHint == resolutionHint;
  }

  @override
  int get hashCode => Object.hash(url, cacheKey, thumbnailUrl, type, resolutionHint);

  @override
  String toString() =>
      'VideoSource(url: $url, type: $type, cacheKey: $cacheKey)';
}
