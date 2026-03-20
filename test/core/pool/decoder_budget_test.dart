import 'package:flutter_test/flutter_test.dart';
import 'package:video_pool/src/core/events/pool_event.dart';
import 'package:video_pool/src/core/pool/decoder_budget.dart';

void main() {
  late GlobalDecoderBudget budget;

  setUp(() {
    budget = GlobalDecoderBudget(totalTokens: 4);
  });

  tearDown(() {
    budget.dispose();
  });

  test('starts with full capacity available', () {
    expect(budget.totalTokens, 4);
    expect(budget.allocations, isEmpty);
  });

  test('requestTokens grants up to available', () {
    final granted = budget.requestTokens('pool_a', 3);
    expect(granted, 3);
    expect(budget.allocations['pool_a'], 3);

    // Only 1 left.
    final granted2 = budget.requestTokens('pool_b', 3);
    expect(granted2, 1);
    expect(budget.allocations['pool_b'], 1);
  });

  test('requestTokens returns 0 when empty', () {
    budget.requestTokens('pool_a', 4);
    final granted = budget.requestTokens('pool_b', 2);
    expect(granted, 0);
    expect(budget.allocations.containsKey('pool_b'), isFalse);
  });

  test('releaseTokens frees tokens for others', () {
    budget.requestTokens('pool_a', 4);
    expect(budget.requestTokens('pool_b', 1), 0);

    budget.releaseTokens('pool_a', 2);
    expect(budget.allocations['pool_a'], 2);

    final granted = budget.requestTokens('pool_b', 2);
    expect(granted, 2);
    expect(budget.allocations['pool_b'], 2);
  });

  test('reduceBudget decreases total and revokes excess', () {
    budget.requestTokens('pool_a', 2);
    budget.requestTokens('pool_b', 2);
    // Budget is 4, allocated 4.

    final reduced = budget.reduceBudget();
    expect(reduced, isTrue);
    expect(budget.totalTokens, 3);

    // One token should have been revoked from the pool with most tokens.
    // Both have 2, so one of them gets revoked to 1.
    final totalAllocated =
        budget.allocations.values.fold(0, (a, b) => a + b);
    expect(totalAllocated, 3);
  });

  test('reduceBudget returns false at minimum', () {
    final minBudget = GlobalDecoderBudget(totalTokens: 1);
    expect(minBudget.reduceBudget(), isFalse);
    expect(minBudget.totalTokens, 1);
    minBudget.dispose();
  });

  test('restoreBudget increases total up to max', () {
    budget.reduceBudget(); // 4 -> 3
    expect(budget.totalTokens, 3);

    final restored = budget.restoreBudget(4);
    expect(restored, isTrue);
    expect(budget.totalTokens, 4);

    // Cannot exceed max.
    final restored2 = budget.restoreBudget(4);
    expect(restored2, isFalse);
    expect(budget.totalTokens, 4);
  });

  test('emits TokenRequestEvent on request', () async {
    final events = <TokenEvent>[];
    budget.tokenEvents.listen(events.add);

    budget.requestTokens('pool_a', 2);

    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(1));
    expect(events.first, isA<TokenRequestEvent>());
    final event = events.first as TokenRequestEvent;
    expect(event.poolId, 'pool_a');
    expect(event.requested, 2);
    expect(event.granted, 2);
  });

  test('emits TokenRevokedEvent on budget reduction', () async {
    final events = <TokenEvent>[];
    budget.tokenEvents.listen(events.add);

    budget.requestTokens('pool_a', 4);
    events.clear();

    budget.reduceBudget();

    await Future<void>.delayed(Duration.zero);

    final revokedEvents = events.whereType<TokenRevokedEvent>().toList();
    expect(revokedEvents, hasLength(1));
    expect(revokedEvents.first.poolId, 'pool_a');
    expect(revokedEvents.first.revokedCount, 1);
    expect(revokedEvents.first.reason, 'budget_reduced');
  });

  test('emits TokenGrantedEvent on release', () async {
    final events = <TokenEvent>[];
    budget.tokenEvents.listen(events.add);

    budget.requestTokens('pool_a', 2);
    events.clear();

    budget.releaseTokens('pool_a', 1);

    await Future<void>.delayed(Duration.zero);

    final grantedEvents = events.whereType<TokenGrantedEvent>().toList();
    expect(grantedEvents, hasLength(1));
    expect(grantedEvents.first.poolId, 'pool_a');
    expect(grantedEvents.first.grantedCount, 1);
  });

  test('multiple pools share budget correctly', () {
    final g1 = budget.requestTokens('feed', 3);
    expect(g1, 3);

    final g2 = budget.requestTokens('pip', 2);
    expect(g2, 1); // Only 1 left.

    expect(budget.allocations, {'feed': 3, 'pip': 1});

    // Feed releases 1.
    budget.releaseTokens('feed', 1);
    expect(budget.allocations, {'feed': 2, 'pip': 1});

    // PiP can now get 1 more.
    final g3 = budget.requestTokens('pip', 1);
    expect(g3, 1);
    expect(budget.allocations, {'feed': 2, 'pip': 2});
  });

  test('releaseTokens clamps to current allocation', () {
    budget.requestTokens('pool_a', 2);
    budget.releaseTokens('pool_a', 10); // Over-release.
    expect(budget.allocations.containsKey('pool_a'), isFalse);
  });

  test('releaseTokens is no-op for unknown pool', () {
    budget.releaseTokens('unknown', 5);
    expect(budget.allocations, isEmpty);
  });
}
