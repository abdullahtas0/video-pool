import 'dart:async';

import '../events/pool_event.dart';

/// Abstract interface for decoder budget management.
///
/// In a multi-pool scenario (e.g. PiP + main feed), multiple [VideoPool]
/// instances compete for a limited number of hardware decoder slots. This
/// interface enables fair, coordinated sharing of that global budget.
///
/// The abstraction allows dependency injection for testing and alternative
/// allocation strategies (e.g. priority-based, weighted).
abstract class DecoderBudget {
  /// Request [desired] tokens for [poolId]. Returns granted count (<= desired).
  int requestTokens(String poolId, int desired);

  /// Release [count] tokens back to the budget for [poolId].
  void releaseTokens(String poolId, int count);

  /// Stream of token-related events (grants, revocations).
  Stream<TokenEvent> get tokenEvents;

  /// Total available tokens in the budget.
  int get totalTokens;

  /// Current allocation per pool (pool ID → token count).
  Map<String, int> get allocations;
}

/// Default implementation using a fixed global token budget.
///
/// Tokens are granted first-come-first-served. When the budget is reduced
/// (e.g. after a decoder init failure), excess tokens are revoked from the
/// pool with the most allocations.
class GlobalDecoderBudget implements DecoderBudget {
  /// Creates a global decoder budget with [totalTokens] slots.
  GlobalDecoderBudget({int totalTokens = 4}) : _totalTokens = totalTokens;

  int _totalTokens;
  final Map<String, int> _allocations = {};
  final StreamController<TokenEvent> _controller =
      StreamController<TokenEvent>.broadcast();

  @override
  int get totalTokens => _totalTokens;

  @override
  Map<String, int> get allocations => Map.unmodifiable(_allocations);

  @override
  Stream<TokenEvent> get tokenEvents => _controller.stream;

  /// Total tokens currently allocated across all pools.
  int get _allocated => _allocations.values.fold(0, (a, b) => a + b);

  /// Tokens available for new requests.
  int get _available => (_totalTokens - _allocated).clamp(0, _totalTokens);

  @override
  int requestTokens(String poolId, int desired) {
    final granted = desired.clamp(0, _available);
    if (granted > 0) {
      _allocations[poolId] = (_allocations[poolId] ?? 0) + granted;
      _controller.add(TokenRequestEvent(
        poolId: poolId,
        requested: desired,
        granted: granted,
      ));
    }
    return granted;
  }

  @override
  void releaseTokens(String poolId, int count) {
    final current = _allocations[poolId] ?? 0;
    final released = count.clamp(0, current);
    if (released > 0) {
      _allocations[poolId] = current - released;
      if (_allocations[poolId] == 0) _allocations.remove(poolId);
      // Notify other pools that tokens became available.
      _controller.add(TokenGrantedEvent(
        poolId: poolId,
        grantedCount: released,
      ));
    }
  }

  /// Reduce total budget (e.g. when decoder init fails).
  ///
  /// Returns `true` if the budget was reduced. If the reduction causes
  /// over-allocation, tokens are revoked from the pool with the most.
  bool reduceBudget() {
    if (_totalTokens <= 1) return false;
    _totalTokens--;

    // If now over-allocated, revoke from least-priority pool.
    if (_allocated > _totalTokens) {
      _revokeExcess();
    }
    return true;
  }

  /// Restore budget after transient failure recovery.
  ///
  /// Returns `true` if the budget was increased (up to [maxBudget]).
  bool restoreBudget(int maxBudget) {
    if (_totalTokens >= maxBudget) return false;
    _totalTokens++;
    return true;
  }

  void _revokeExcess() {
    while (_allocated > _totalTokens) {
      // Find pool with most tokens and revoke 1.
      String? targetPool;
      var maxTokens = 0;
      for (final entry in _allocations.entries) {
        if (entry.value > maxTokens) {
          maxTokens = entry.value;
          targetPool = entry.key;
        }
      }
      if (targetPool == null) break;
      _allocations[targetPool] = maxTokens - 1;
      if (_allocations[targetPool] == 0) _allocations.remove(targetPool);
      _controller.add(TokenRevokedEvent(
        poolId: targetPool,
        revokedCount: 1,
        reason: 'budget_reduced',
      ));
    }
  }

  /// Dispose the stream controller.
  void dispose() {
    _controller.close();
  }
}
