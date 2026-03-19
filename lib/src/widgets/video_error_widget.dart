import 'package:flutter/material.dart';

/// Error UI shown when a video fails to load or play.
///
/// Displays an error icon, optional message, and a retry button.
/// Styled to match the app's Material theme.
class VideoErrorWidget extends StatelessWidget {
  /// Creates a [VideoErrorWidget].
  const VideoErrorWidget({
    super.key,
    this.errorMessage,
    this.onRetry,
  });

  /// Human-readable error description. If null, a generic message is shown.
  final String? errorMessage;

  /// Called when the user taps the retry button.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                color: colorScheme.error,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                errorMessage ?? 'Failed to load video',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                ),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tap to retry'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
