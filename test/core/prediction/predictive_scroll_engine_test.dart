import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_pool/src/core/prediction/predictive_scroll_engine.dart';

void main() {
  const engine = PredictiveScrollEngine();
  const itemExtent = 800.0; // typical phone screen height
  const itemCount = 100;

  group('PredictiveScrollEngine', () {
    test('returns null for low velocity', () {
      final result = engine.predict(
        position: 0.0,
        velocity: 100.0, // well below 0.5 * 800 = 400
        itemExtent: itemExtent,
        itemCount: itemCount,
        platform: TargetPlatform.android,
      );

      expect(result, isNull);
    });

    test('returns null for zero velocity', () {
      final result = engine.predict(
        position: 800.0,
        velocity: 0.0,
        itemExtent: itemExtent,
        itemCount: itemCount,
        platform: TargetPlatform.android,
      );

      expect(result, isNull);
    });

    test('returns null for invalid itemExtent', () {
      final result = engine.predict(
        position: 0.0,
        velocity: 5000.0,
        itemExtent: 0.0,
        itemCount: itemCount,
        platform: TargetPlatform.android,
      );

      expect(result, isNull);
    });

    test('returns null for zero itemCount', () {
      final result = engine.predict(
        position: 0.0,
        velocity: 5000.0,
        itemExtent: itemExtent,
        itemCount: 0,
        platform: TargetPlatform.android,
      );

      expect(result, isNull);
    });

    test('predicts target index for moderate velocity', () {
      final result = engine.predict(
        position: 0.0,
        velocity: 3000.0, // moderate forward scroll
        itemExtent: itemExtent,
        itemCount: itemCount,
        platform: TargetPlatform.android,
      );

      expect(result, isNotNull);
      expect(result!.targetIndex, greaterThan(0));
      expect(result.targetIndex, lessThan(itemCount));
      expect(result.confidence, greaterThan(0.0));
      expect(result.confidence, lessThanOrEqualTo(1.0));
      expect(result.estimatedArrivalMs, greaterThan(0));
    });

    test('clamps to valid range (0 to itemCount-1)', () {
      // Very high velocity that would overshoot.
      final result = engine.predict(
        position: 79000.0, // near end
        velocity: 50000.0,
        itemExtent: itemExtent,
        itemCount: itemCount,
        platform: TargetPlatform.android,
      );

      expect(result, isNotNull);
      expect(result!.targetIndex, lessThanOrEqualTo(itemCount - 1));
      expect(result.targetIndex, greaterThanOrEqualTo(0));
    });

    test('clamps to 0 for large negative velocity at start', () {
      final result = engine.predict(
        position: 800.0, // at index 1
        velocity: -50000.0,
        itemExtent: itemExtent,
        itemCount: itemCount,
        platform: TargetPlatform.android,
      );

      expect(result, isNotNull);
      expect(result!.targetIndex, 0);
    });

    test('negative velocity predicts backward scroll', () {
      final result = engine.predict(
        position: 8000.0, // at index 10
        velocity: -3000.0,
        itemExtent: itemExtent,
        itemCount: itemCount,
        platform: TargetPlatform.android,
      );

      expect(result, isNotNull);
      // Should predict an index lower than current position / itemExtent.
      expect(result!.targetIndex, lessThan(10));
    });

    test('confidence decreases with higher velocity', () {
      final slowResult = engine.predict(
        position: 0.0,
        velocity: 500.0, // just above threshold (400)
        itemExtent: itemExtent,
        itemCount: itemCount,
        platform: TargetPlatform.android,
      );

      final fastResult = engine.predict(
        position: 0.0,
        velocity: 6000.0,
        itemExtent: itemExtent,
        itemCount: itemCount,
        platform: TargetPlatform.android,
      );

      expect(slowResult, isNotNull);
      expect(fastResult, isNotNull);
      expect(slowResult!.confidence, greaterThan(fastResult!.confidence));
    });

    test('uses iOS physics for TargetPlatform.iOS', () {
      // iOS uses friction = 0.135, so final = position + velocity / 0.135
      // For velocity = 1000, that's 0 + 1000 / 0.135 ~ 7407 pixels ~ index 9
      final result = engine.predict(
        position: 0.0,
        velocity: 1000.0,
        itemExtent: itemExtent,
        itemCount: itemCount,
        platform: TargetPlatform.iOS,
      );

      expect(result, isNotNull);
      // iOS deceleration is much less aggressive, so prediction goes further.
      final expectedIndex = (1000.0 / 0.135 / itemExtent).round();
      expect(result!.targetIndex, expectedIndex);
    });

    test('uses Android physics for TargetPlatform.android', () {
      // Android uses decelerationFactor = 0.26, so final = position + velocity * 0.26
      // For velocity = 5000, that's 0 + 5000 * 0.26 = 1300 pixels ~ index 2
      final result = engine.predict(
        position: 0.0,
        velocity: 5000.0,
        itemExtent: itemExtent,
        itemCount: itemCount,
        platform: TargetPlatform.android,
      );

      expect(result, isNotNull);
      final expectedIndex = (5000.0 * 0.26 / itemExtent).round();
      expect(result!.targetIndex, expectedIndex);
    });

    test('iOS predicts further than Android for same velocity', () {
      const velocity = 5000.0;

      final iosResult = engine.predict(
        position: 0.0,
        velocity: velocity,
        itemExtent: itemExtent,
        itemCount: itemCount,
        platform: TargetPlatform.iOS,
      );

      final androidResult = engine.predict(
        position: 0.0,
        velocity: velocity,
        itemExtent: itemExtent,
        itemCount: itemCount,
        platform: TargetPlatform.android,
      );

      expect(iosResult, isNotNull);
      expect(androidResult, isNotNull);
      // iOS friction-based deceleration carries much further.
      expect(iosResult!.targetIndex, greaterThan(androidResult!.targetIndex));
    });
  });
}
