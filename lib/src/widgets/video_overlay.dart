import 'package:flutter/material.dart';

import '../core/lifecycle/lifecycle_state.dart';

/// Overlay shown on top of the video surface for play/pause controls
/// and loading indicators.
///
/// Displays different UI based on the current [lifecycleState]:
/// - [LifecycleState.playing] — tap area with optional pause icon
/// - [LifecycleState.paused] — play icon overlay
/// - [LifecycleState.buffering] — loading spinner
/// - [LifecycleState.preparing] — loading spinner
class VideoOverlay extends StatelessWidget {
  /// Creates a [VideoOverlay].
  const VideoOverlay({
    super.key,
    required this.lifecycleState,
    this.onTap,
    this.showControls = true,
  });

  /// The current lifecycle state of the video.
  final LifecycleState lifecycleState;

  /// Called when the overlay is tapped (typically to toggle play/pause).
  final VoidCallback? onTap;

  /// Whether to show play/pause control icons.
  final bool showControls;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: _buildOverlayContent(),
    );
  }

  Widget _buildOverlayContent() {
    switch (lifecycleState) {
      case LifecycleState.buffering:
      case LifecycleState.preparing:
        return const Center(
          child: CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 3.0,
          ),
        );

      case LifecycleState.paused:
        if (!showControls) return const SizedBox.expand();
        return Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.black45,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.play_arrow,
              color: Colors.white,
              size: 40,
            ),
          ),
        );

      case LifecycleState.playing:
        // Transparent tap area — no visible controls while playing.
        return const SizedBox.expand();

      default:
        return const SizedBox.expand();
    }
  }
}
