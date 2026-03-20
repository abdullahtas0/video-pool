import 'package:flutter_test/flutter_test.dart';
import 'package:video_pool/src/core/events/event_ring_buffer.dart';
import 'package:video_pool/src/core/events/metrics_snapshot.dart';
import 'package:video_pool/src/core/events/pool_event.dart';
import 'package:video_pool/src/core/memory/memory_pressure_level.dart';
import 'package:video_pool/src/core/models/thermal_status.dart';

void main() {
  group('MetricsSnapshot', () {
    test('fromBuffer with empty buffer returns zeros', () {
      final buffer = EventRingBuffer(capacity: 10);
      final snapshot = MetricsSnapshot.fromBuffer(buffer);

      expect(snapshot.cacheHitRate, 0.0);
      expect(snapshot.avgSwapLatencyMs, 0.0);
      expect(snapshot.throttleCount, 0);
      expect(snapshot.totalEvents, 0);
      expect(snapshot.computedAt, greaterThan(0));
    });

    test('cacheHitRate computed from CacheEvents', () {
      final buffer = EventRingBuffer(capacity: 10);

      // 3 hits + 1 miss = 0.75
      buffer.add(CacheEvent(
          cacheKey: 'a', action: CacheAction.hit, sizeBytes: 100));
      buffer.add(CacheEvent(
          cacheKey: 'b', action: CacheAction.hit, sizeBytes: 200));
      buffer.add(CacheEvent(
          cacheKey: 'c', action: CacheAction.hit, sizeBytes: 300));
      buffer.add(CacheEvent(
          cacheKey: 'd', action: CacheAction.miss, sizeBytes: 400));

      final snapshot = MetricsSnapshot.fromBuffer(buffer);

      expect(snapshot.cacheHitRate, 0.75);
      expect(snapshot.totalEvents, 4);
    });

    test('avgSwapLatencyMs computed from SwapEvents', () {
      final buffer = EventRingBuffer(capacity: 10);

      buffer.add(SwapEvent(
        entryId: 0,
        fromIndex: 0,
        toIndex: 1,
        durationMs: 2,
        isWarmStart: false,
      ));
      buffer.add(SwapEvent(
        entryId: 0,
        fromIndex: 0,
        toIndex: 1,
        durationMs: 4,
        isWarmStart: false,
      ));

      final snapshot = MetricsSnapshot.fromBuffer(buffer);

      expect(snapshot.avgSwapLatencyMs, 3.0);
    });

    test('throttleCount counts ThrottleEvents', () {
      final buffer = EventRingBuffer(capacity: 10);

      buffer.add(ThrottleEvent(
        thermalLevel: ThermalLevel.serious,
        memoryPressure: MemoryPressureLevel.normal,
        effectiveMaxConcurrent: 2,
      ));
      buffer.add(ThrottleEvent(
        thermalLevel: ThermalLevel.serious,
        memoryPressure: MemoryPressureLevel.normal,
        effectiveMaxConcurrent: 1,
      ));

      final snapshot = MetricsSnapshot.fromBuffer(buffer);

      expect(snapshot.throttleCount, 2);
    });

    test('totalEvents counts all events', () {
      final buffer = EventRingBuffer(capacity: 10);

      buffer.add(ErrorEvent(
          code: 'ERR_1', message: 'Something failed', fatal: false));
      buffer.add(ErrorEvent(
          code: 'ERR_2', message: 'Something else failed', fatal: true));

      final snapshot = MetricsSnapshot.fromBuffer(buffer);

      expect(snapshot.totalEvents, 2);
    });

    test('evict CacheAction excluded from hit rate', () {
      final buffer = EventRingBuffer(capacity: 10);

      buffer.add(CacheEvent(
          cacheKey: 'a', action: CacheAction.hit, sizeBytes: 100));
      buffer.add(CacheEvent(
          cacheKey: 'b', action: CacheAction.evict, sizeBytes: 200));

      final snapshot = MetricsSnapshot.fromBuffer(buffer);

      // evict should not count toward hit rate, so 1 hit / (1 hit + 0 miss) = 1.0
      expect(snapshot.cacheHitRate, 1.0);
    });
  });
}
