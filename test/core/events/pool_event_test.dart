import 'package:flutter_test/flutter_test.dart';
import 'package:video_pool/src/core/events/pool_event.dart';
import 'package:video_pool/src/core/lifecycle/lifecycle_state.dart';
import 'package:video_pool/src/core/memory/memory_pressure_level.dart';
import 'package:video_pool/src/core/models/thermal_status.dart';

void main() {
  group('SwapEvent', () {
    test('stores all fields and has a positive timestamp', () {
      final event = SwapEvent(
        entryId: 1,
        fromIndex: 0,
        toIndex: 3,
        durationMs: 42,
        isWarmStart: true,
      );

      expect(event.entryId, 1);
      expect(event.fromIndex, 0);
      expect(event.toIndex, 3);
      expect(event.durationMs, 42);
      expect(event.isWarmStart, isTrue);
      expect(event.timestamp, greaterThan(0));
    });
  });

  group('ReconcileEvent', () {
    test('stores plan counts', () {
      final event = ReconcileEvent(
        primaryIndex: 5,
        playCount: 1,
        preloadCount: 2,
        pauseCount: 3,
        releaseCount: 4,
      );

      expect(event.primaryIndex, 5);
      expect(event.playCount, 1);
      expect(event.preloadCount, 2);
      expect(event.pauseCount, 3);
      expect(event.releaseCount, 4);
    });
  });

  group('ThrottleEvent', () {
    test('stores device state', () {
      final event = ThrottleEvent(
        thermalLevel: ThermalLevel.serious,
        memoryPressure: MemoryPressureLevel.critical,
        effectiveMaxConcurrent: 1,
      );

      expect(event.thermalLevel, ThermalLevel.serious);
      expect(event.memoryPressure, MemoryPressureLevel.critical);
      expect(event.effectiveMaxConcurrent, 1);
    });
  });

  group('CacheEvent', () {
    test('stores action and optional downloadDurationMs', () {
      final hit = CacheEvent(
        cacheKey: 'video_abc',
        action: CacheAction.hit,
        sizeBytes: 2048,
      );

      expect(hit.cacheKey, 'video_abc');
      expect(hit.action, CacheAction.hit);
      expect(hit.sizeBytes, 2048);
      expect(hit.downloadDurationMs, isNull);

      final prefetch = CacheEvent(
        cacheKey: 'video_xyz',
        action: CacheAction.prefetchComplete,
        sizeBytes: 1024000,
        downloadDurationMs: 350,
      );

      expect(prefetch.downloadDurationMs, 350);
    });
  });

  group('LifecycleEvent', () {
    test('stores state transition', () {
      final event = LifecycleEvent(
        entryId: 2,
        index: 7,
        fromState: LifecycleState.idle,
        toState: LifecycleState.preparing,
      );

      expect(event.entryId, 2);
      expect(event.index, 7);
      expect(event.fromState, LifecycleState.idle);
      expect(event.toState, LifecycleState.preparing);
    });
  });

  group('EmergencyFlushEvent', () {
    test('stores survivor and disposed count', () {
      final event = EmergencyFlushEvent(
        survivorEntryId: 0,
        disposedCount: 3,
      );

      expect(event.survivorEntryId, 0);
      expect(event.disposedCount, 3);
    });
  });

  group('BandwidthSampleEvent', () {
    test('stores bandwidth measurement fields', () {
      final event = BandwidthSampleEvent(
        bytesReceived: 2 * 1024 * 1024,
        durationMs: 500,
        estimatedBytesPerSec: 4 * 1024 * 1024,
        concurrentDownloadsCount: 1,
      );

      expect(event.bytesReceived, 2 * 1024 * 1024);
      expect(event.durationMs, 500);
      expect(event.estimatedBytesPerSec, 4 * 1024 * 1024);
      expect(event.concurrentDownloadsCount, 1);
      expect(event.timestamp, greaterThan(0));
    });
  });

  group('ErrorEvent', () {
    test('stores code, message, and fatal flag', () {
      final event = ErrorEvent(
        code: 'SWAP_TIMEOUT',
        message: 'Swap took longer than 5 seconds',
        fatal: true,
      );

      expect(event.code, 'SWAP_TIMEOUT');
      expect(event.message, 'Swap took longer than 5 seconds');
      expect(event.fatal, isTrue);
    });
  });

  group('PredictionEvent', () {
    test('stores prediction fields with null actualIndex', () {
      final event = PredictionEvent(
        predictedIndex: 5,
        confidence: 0.85,
      );

      expect(event.predictedIndex, 5);
      expect(event.confidence, 0.85);
      expect(event.actualIndex, isNull);
      expect(event.timestamp, greaterThan(0));
    });

    test('stores resolved prediction with actualIndex', () {
      final event = PredictionEvent(
        predictedIndex: 5,
        confidence: 0.0,
        actualIndex: 6,
      );

      expect(event.predictedIndex, 5);
      expect(event.confidence, 0.0);
      expect(event.actualIndex, 6);
    });
  });

  group('Exhaustive switch', () {
    test('sealed class enables exhaustive switching on all 9 types', () {
      final PoolEvent event = SwapEvent(
        entryId: 1,
        fromIndex: 0,
        toIndex: 1,
        durationMs: 10,
        isWarmStart: false,
      );

      final label = switch (event) {
        SwapEvent() => 'swap',
        ReconcileEvent() => 'reconcile',
        ThrottleEvent() => 'throttle',
        CacheEvent() => 'cache',
        LifecycleEvent() => 'lifecycle',
        EmergencyFlushEvent() => 'emergency',
        BandwidthSampleEvent() => 'bandwidth',
        ErrorEvent() => 'error',
        PredictionEvent() => 'prediction',
      };

      expect(label, 'swap');
    });
  });
}
