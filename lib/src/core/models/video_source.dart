import 'package:flutter/foundation.dart';

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

  /// Creates a copy of this [VideoSource] with the given fields replaced.
  VideoSource copyWith({
    String? url,
    Map<String, String>? headers,
    String? cacheKey,
    String? thumbnailUrl,
    VideoSourceType? type,
  }) {
    return VideoSource(
      url: url ?? this.url,
      headers: headers ?? this.headers,
      cacheKey: cacheKey ?? this.cacheKey,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      type: type ?? this.type,
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
        other.type == type;
  }

  @override
  int get hashCode => Object.hash(url, cacheKey, thumbnailUrl, type);

  @override
  String toString() =>
      'VideoSource(url: $url, type: $type, cacheKey: $cacheKey)';
}
