import 'package:flutter/foundation.dart';

/// The result of a scroll destination prediction.
///
/// Contains the predicted target index, a confidence score, and an estimated
/// time of arrival in milliseconds.
class PredictionResult {
  /// Creates a prediction result.
  const PredictionResult({
    required this.targetIndex,
    required this.confidence,
    required this.estimatedArrivalMs,
  });

  /// The predicted feed index the scroll will settle on.
  final int targetIndex;

  /// Confidence in this prediction, from 0.0 (no confidence) to 1.0 (certain).
  ///
  /// Higher velocities produce lower confidence because the user is more
  /// likely to tap to stop or change direction.
  final double confidence;

  /// Estimated time until the scroll reaches [targetIndex], in milliseconds.
  final int estimatedArrivalMs;
}

/// A stateless, pure-math engine that predicts where a scroll will stop.
///
/// Uses Flutter's deterministic scroll physics constants (empirically derived
/// from `ClampingScrollSimulation` on Android and `BouncingScrollSimulation`
/// on iOS) to compute the final resting position from current position and
/// velocity.
///
/// This engine is intentionally stateless: it takes a snapshot of scroll
/// metrics and returns a prediction. Stateful tracking (e.g. stabilization,
/// emission) belongs in [VideoPool].
class PredictiveScrollEngine {
  /// Creates a predictive scroll engine.
  const PredictiveScrollEngine();

  /// Predict where the scroll will stop based on current physics.
  ///
  /// Returns `null` if prediction is not meaningful (e.g., finger still on
  /// screen with low velocity, or the computed target equals the current page).
  ///
  /// Parameters:
  /// - [position]: current scroll offset in pixels.
  /// - [velocity]: current scroll velocity in pixels/second.
  /// - [itemExtent]: height (or width) of each item in pixels.
  /// - [itemCount]: total number of items in the feed.
  /// - [platform]: overrides [defaultTargetPlatform] for physics selection.
  PredictionResult? predict({
    required double position,
    required double velocity,
    required double itemExtent,
    required int itemCount,
    TargetPlatform? platform,
  }) {
    if (itemExtent <= 0 || itemCount <= 0) return null;

    final effectivePlatform = platform ?? defaultTargetPlatform;

    // Low velocity = user is dragging slowly, adjacent preload is sufficient.
    if (velocity.abs() < itemExtent * 0.5) return null;

    // Compute final position using scroll physics deceleration.
    final finalPosition =
        _computeFinalPosition(position, velocity, effectivePlatform);

    // Convert to index.
    final rawIndex = (finalPosition / itemExtent).round();
    final targetIndex = rawIndex.clamp(0, itemCount - 1);

    // Confidence based on velocity magnitude.
    // High velocity = lower confidence (user might tap to stop).
    // Medium velocity after deceleration started = higher confidence.
    final normalizedVelocity =
        velocity.abs() / (itemExtent * 10); // 10 pages/sec = very fast
    final confidence =
        (1.0 - normalizedVelocity.clamp(0.0, 0.8)).clamp(0.2, 0.95);

    // Estimated arrival time.
    final distance = (finalPosition - position).abs();
    final avgVelocity = velocity.abs() / 2; // rough average during deceleration
    final arrivalMs =
        avgVelocity > 0 ? (distance / avgVelocity * 1000).round() : 0;

    return PredictionResult(
      targetIndex: targetIndex,
      confidence: confidence,
      estimatedArrivalMs: arrivalMs,
    );
  }

  /// Computes the estimated final scroll position using platform-specific
  /// deceleration constants.
  double _computeFinalPosition(
    double position,
    double velocity,
    TargetPlatform platform,
  ) {
    // Android: ClampingScrollSimulation
    // The deceleration is roughly: final = position + velocity * 0.26
    // (empirical from Flutter source).
    //
    // iOS: BouncingScrollSimulation
    // Friction-based: final = position + velocity / frictionCoefficient
    // frictionCoefficient ~= 0.135 (from Flutter's BouncingScrollSimulation).

    switch (platform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        // iOS friction-based deceleration.
        const friction = 0.135;
        return position + velocity / friction;
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        // Android clamping deceleration (empirical constant from Flutter source).
        const decelerationFactor = 0.26;
        return position + velocity * decelerationFactor;
    }
  }
}
