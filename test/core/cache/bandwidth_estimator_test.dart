import 'package:flutter_test/flutter_test.dart';
import 'package:video_pool/src/core/cache/bandwidth_estimator.dart';

void main() {
  late BandwidthEstimator estimator;

  setUp(() {
    estimator = BandwidthEstimator();
  });

  group('BandwidthEstimator', () {
    test('returns null before any samples', () {
      expect(estimator.estimatedBytesPerSec, isNull);
    });

    test('first sample uses direct assignment', () {
      // 1 MB in 1000ms = 1 MB/s = 1048576 bytes/sec
      estimator.addSample(1024 * 1024, 1000);
      expect(estimator.estimatedBytesPerSec, 1024 * 1024);
    });

    test('subsequent samples use EMA', () {
      // First sample: 1 MB in 1s = 1 MB/s
      estimator.addSample(1024 * 1024, 1000);
      final first = estimator.estimatedBytesPerSec!;

      // Second sample: 2 MB in 1s = 2 MB/s
      estimator.addSample(2 * 1024 * 1024, 1000);
      final second = estimator.estimatedBytesPerSec!;

      // EMA: 0.3 * 2MB/s + 0.7 * 1MB/s should be between 1 and 2 MB/s
      expect(second, greaterThan(first));
      expect(second, lessThan(2 * 1024 * 1024));

      // Exact: 0.3 * 2097152 + 0.7 * 1048576 = 629145.6 + 734003.2 = 1363148.8 ≈ 1363149
      final expected =
          (0.3 * 2 * 1024 * 1024 + 0.7 * 1024 * 1024).round();
      expect(second, expected);
    });

    test('ignores zero duration', () {
      estimator.addSample(1024, 0);
      expect(estimator.estimatedBytesPerSec, isNull);
    });

    test('ignores negative duration', () {
      estimator.addSample(1024, -100);
      expect(estimator.estimatedBytesPerSec, isNull);
    });

    test('ignores zero bytes', () {
      estimator.addSample(0, 1000);
      expect(estimator.estimatedBytesPerSec, isNull);
    });

    test('ignores negative bytes', () {
      estimator.addSample(-100, 1000);
      expect(estimator.estimatedBytesPerSec, isNull);
    });

    test('concurrency bias correction', () {
      // 1 MB in 1s with 2 concurrent downloads.
      // Single stream rate = 1 MB/s, total estimated = 2 MB/s.
      estimator.addSample(1024 * 1024, 1000, concurrentDownloads: 2);
      expect(estimator.estimatedBytesPerSec, 2 * 1024 * 1024);
    });

    test('reset clears estimate', () {
      estimator.addSample(1024 * 1024, 1000);
      expect(estimator.estimatedBytesPerSec, isNotNull);

      estimator.reset();
      expect(estimator.estimatedBytesPerSec, isNull);

      // After reset, next sample should be treated as first (direct assignment)
      estimator.addSample(512 * 1024, 1000);
      expect(estimator.estimatedBytesPerSec, 512 * 1024);
    });
  });
}
