import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:video_pool/video_pool.dart';

import '../../mocks/mock_player_adapter.dart';

void main() {
  late MemoryManager manager;

  setUp(() {
    manager = MemoryManager(budgetBytes: 100 * 1024 * 1024); // 100MB
  });

  setUpAll(() {
    registerPlayerAdapterFallbacks();
  });

  PoolEntry createEntry(int id, {int memoryBytes = 30 * 1024 * 1024}) {
    final adapter = MockPlayerAdapter();
    when(() => adapter.estimatedMemoryBytes).thenReturn(memoryBytes);
    when(() => adapter.stateNotifier).thenReturn(
      ValueNotifier(const PlayerState()),
    );
    return PoolEntry(id: id, adapter: adapter);
  }

  group('MemoryManager', () {
    test('tracks entries and reports current usage', () {
      final entry1 = createEntry(0, memoryBytes: 20 * 1024 * 1024);
      final entry2 = createEntry(1, memoryBytes: 30 * 1024 * 1024);

      manager.track(entry1);
      manager.track(entry2);

      expect(manager.currentUsageBytes, 50 * 1024 * 1024);
    });

    test('untracks entries', () {
      final entry = createEntry(0, memoryBytes: 20 * 1024 * 1024);
      manager.track(entry);
      expect(manager.currentUsageBytes, 20 * 1024 * 1024);

      manager.untrack(0);
      expect(manager.currentUsageBytes, 0);
    });

    test('wouldExceedBudget returns correct result', () {
      final entry = createEntry(0, memoryBytes: 80 * 1024 * 1024);
      manager.track(entry);

      // 80MB used + 10MB = 90MB < 100MB budget
      expect(manager.wouldExceedBudget(10 * 1024 * 1024), isFalse);
      // 80MB used + 30MB = 110MB > 100MB budget
      expect(manager.wouldExceedBudget(30 * 1024 * 1024), isTrue);
    });

    test('getEvictionCandidates returns idle entries in LRU order', () {
      final entry1 = createEntry(0, memoryBytes: 20 * 1024 * 1024);
      final entry2 = createEntry(1, memoryBytes: 30 * 1024 * 1024);
      final entry3 = createEntry(2, memoryBytes: 25 * 1024 * 1024);

      // Entry1 is oldest, entry3 is newest.
      entry1.lastUsed = DateTime(2024, 1, 1);
      entry2.lastUsed = DateTime(2024, 1, 2);
      entry3.lastUsed = DateTime(2024, 1, 3);

      // All are idle (no assignedIndex).
      manager.track(entry1);
      manager.track(entry2);
      manager.track(entry3);

      final candidates = manager.getEvictionCandidates(40 * 1024 * 1024);
      expect(candidates.length, 2); // entry1 (20MB) + entry2 (30MB) >= 40MB
      expect(candidates[0].id, 0);
      expect(candidates[1].id, 1);
    });

    test('getEvictionCandidates skips assigned entries', () {
      final entry1 = createEntry(0, memoryBytes: 20 * 1024 * 1024);
      final entry2 = createEntry(1, memoryBytes: 30 * 1024 * 1024);

      entry1.lastUsed = DateTime(2024, 1, 1);
      entry2.lastUsed = DateTime(2024, 1, 2);

      // Assign entry1 to an index — it should not be evicted.
      entry1.assignTo(5, const VideoSource(url: 'https://example.com/v.mp4'));

      manager.track(entry1);
      manager.track(entry2);

      final candidates = manager.getEvictionCandidates(50 * 1024 * 1024);
      expect(candidates.length, 1);
      expect(candidates[0].id, 1); // Only entry2 is idle.
    });

    group('scaleBudget', () {
      test('normal = 100% of budget', () {
        manager.scaleBudget(MemoryPressureLevel.normal);
        expect(manager.effectiveBudgetBytes, 100 * 1024 * 1024);
      });

      test('warning = 75% of budget', () {
        manager.scaleBudget(MemoryPressureLevel.warning);
        expect(manager.effectiveBudgetBytes, (100 * 1024 * 1024 * 0.75).round());
      });

      test('critical = 50% of budget', () {
        manager.scaleBudget(MemoryPressureLevel.critical);
        expect(manager.effectiveBudgetBytes, (100 * 1024 * 1024 * 0.50).round());
      });

      test('terminal = 25% of budget', () {
        manager.scaleBudget(MemoryPressureLevel.terminal);
        expect(manager.effectiveBudgetBytes, (100 * 1024 * 1024 * 0.25).round());
      });
    });

    test('emergencyFlush returns all except primary', () {
      final entry1 = createEntry(0);
      final entry2 = createEntry(1);
      final entry3 = createEntry(2);

      manager.track(entry1);
      manager.track(entry2);
      manager.track(entry3);

      final toEvict = manager.emergencyFlush(1); // Keep entry 1.
      expect(toEvict.length, 2);
      expect(toEvict.map((e) => e.id).toSet(), {0, 2});
    });

    test('emergencyFlush with null primary returns all', () {
      final entry1 = createEntry(0);
      final entry2 = createEntry(1);

      manager.track(entry1);
      manager.track(entry2);

      final toEvict = manager.emergencyFlush(null);
      expect(toEvict.length, 2);
    });

    test('resetBudget restores original budget', () {
      manager.scaleBudget(MemoryPressureLevel.critical);
      expect(manager.effectiveBudgetBytes, isNot(100 * 1024 * 1024));

      manager.resetBudget();
      expect(manager.effectiveBudgetBytes, 100 * 1024 * 1024);
    });
  });
}
