import 'package:flutter/material.dart';

/// Placeholder widget shown before video playback begins.
///
/// Shows [Image.network] if a [thumbnailUrl] is provided, otherwise
/// falls back to the custom [placeholder] widget or a black container.
class VideoThumbnail extends StatelessWidget {
  /// Creates a [VideoThumbnail].
  const VideoThumbnail({
    super.key,
    this.thumbnailUrl,
    this.fit = BoxFit.cover,
    this.placeholder,
  });

  /// URL of the thumbnail image. If null, [placeholder] is shown instead.
  final String? thumbnailUrl;

  /// How the thumbnail image should be inscribed into the available space.
  final BoxFit fit;

  /// Custom placeholder widget shown when [thumbnailUrl] is null.
  ///
  /// If both [thumbnailUrl] and [placeholder] are null, a black container
  /// is shown.
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    if (thumbnailUrl != null && thumbnailUrl!.isNotEmpty) {
      return Image.network(
        thumbnailUrl!,
        fit: fit,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stackTrace) {
          return placeholder ?? _defaultPlaceholder();
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Stack(
            fit: StackFit.expand,
            children: [
              placeholder ?? _defaultPlaceholder(),
              Center(
                child: CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                      : null,
                  strokeWidth: 2.0,
                  color: Colors.white54,
                ),
              ),
            ],
          );
        },
      );
    }

    return placeholder ?? _defaultPlaceholder();
  }

  Widget _defaultPlaceholder() {
    return Container(color: Colors.black);
  }
}
