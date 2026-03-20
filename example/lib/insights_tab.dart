import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_pool/video_pool.dart';

/// Live analytics dashboard showing real-time pool metrics, entry states,
/// device conditions, and a scrolling event stream.
///
/// Receives a [VideoPool] reference from the parent and subscribes to
/// [VideoPool.eventStream] for live updates.
class InsightsTab extends StatefulWidget {
  const InsightsTab({super.key, required this.pool});

  /// The shared pool instance (from the Feed tab).
  final VideoPool pool;

  @override
  State<InsightsTab> createState() => _InsightsTabState();
}

class _InsightsTabState extends State<InsightsTab> {
  final List<_EventRecord> _recentEvents = [];
  StreamSubscription<PoolEvent>? _sub;
  MetricsSnapshot? _metrics;
  PoolStatistics? _stats;

  // Tracked entry models (built from events).
  final Map<int, _EntryModel> _entries = {};

  // Device state.
  ThermalLevel _thermalLevel = ThermalLevel.nominal;
  MemoryPressureLevel _memoryPressure = MemoryPressureLevel.normal;
  int _effectiveMaxConcurrent = 3;

  static const _maxEvents = 50;
  Timer? _throttleTimer;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _metrics = widget.pool.metrics;
    _stats = widget.pool.statistics;
    _sub = widget.pool.eventStream.listen(_onEvent);
    // Throttle UI updates to max ~5 per second
    _throttleTimer = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) {
        if (_dirty && mounted) {
          _dirty = false;
          setState(() {
            _metrics = widget.pool.metrics;
            _stats = widget.pool.statistics;
          });
        }
      },
    );
  }

  @override
  void didUpdateWidget(InsightsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pool != widget.pool) {
      _sub?.cancel();
      _sub = widget.pool.eventStream.listen(_onEvent);
      _entries.clear();
      _recentEvents.clear();
    }
  }

  void _onEvent(PoolEvent event) {
    if (!mounted) return;

    // Accumulate data without setState — throttle timer handles UI updates.
    final record = _EventRecord.fromEvent(event);
    _recentEvents.insert(0, record);
    if (_recentEvents.length > _maxEvents) _recentEvents.removeLast();
    _dirty = true;

    // Update tracked models.
    switch (event) {
      case SwapEvent(:final entryId, :final toIndex):
        _entries[entryId] = _EntryModel(
          entryId: entryId,
          assignedIndex: toIndex,
          state: 'READY',
          );
        case LifecycleEvent(:final entryId, :final index, :final toState):
          _entries[entryId] = _EntryModel(
            entryId: entryId,
            assignedIndex: index,
            state: toState.name.toUpperCase(),
          );
        case ReconcileEvent(:final primaryIndex):
          // Mark the primary entry.
          for (final entry in _entries.values) {
            entry.isPrimary = entry.assignedIndex == primaryIndex;
          }
        case ThrottleEvent(
            :final thermalLevel,
            :final memoryPressure,
            :final effectiveMaxConcurrent,
          ):
          _thermalLevel = thermalLevel;
          _memoryPressure = memoryPressure;
          _effectiveMaxConcurrent = effectiveMaxConcurrent;
        case EmergencyFlushEvent(:final survivorEntryId, :final disposedCount):
          // Remove disposed entries.
          _entries.removeWhere(
            (id, _) => id != survivorEntryId,
          );
          if (disposedCount > 0) {
            // Keep only the survivor.
          }
        case _:
          break;
      }
  }

  @override
  void dispose() {
    _throttleTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0A0A1A),
      child: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Header
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Live Insights',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),

            // Metrics grid (2x2)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _MetricsGrid(
                  metrics: _metrics,
                  stats: _stats,
                ),
              ),
            ),

            // Section: Pool Entries
            const SliverToBoxAdapter(
              child: _SectionHeader(title: 'Pool Entries'),
            ),
            SliverToBoxAdapter(
              child: _PoolEntriesRow(
                entries: _entries.values.toList(),
                maxConcurrent: widget.pool.config.maxConcurrent,
              ),
            ),

            // Section: Device Status
            const SliverToBoxAdapter(
              child: _SectionHeader(title: 'Device Status'),
            ),
            SliverToBoxAdapter(
              child: _DeviceStatusRow(
                thermalLevel: _thermalLevel,
                memoryPressure: _memoryPressure,
                effectiveMaxConcurrent: _effectiveMaxConcurrent,
              ),
            ),

            // Section: Event Stream
            const SliverToBoxAdapter(
              child: _SectionHeader(title: 'Event Stream'),
            ),
            SliverToBoxAdapter(
              child: _EventStreamPanel(events: _recentEvents),
            ),

            // Bottom padding
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Metrics Grid
// ---------------------------------------------------------------------------

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.metrics, required this.stats});

  final MetricsSnapshot? metrics;
  final PoolStatistics? stats;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final cacheHitRate = m != null ? (m.cacheHitRate * 100) : 0.0;
    final bandwidth = m != null
        ? (m.avgBandwidthBytesPerSec / (1024 * 1024))
        : 0.0;
    final avgSwap = m?.avgSwapLatencyMs ?? 0.0;
    final prediction = m != null ? (m.predictionAccuracy * 100) : 0.0;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: 'Cache Hit Rate',
                value: '${cacheHitRate.toStringAsFixed(1)}%',
                color: const Color(0xFF4CAF50),
                icon: Icons.cached,
              ),
            ),
            Expanded(
              child: _MetricCard(
                label: 'Bandwidth',
                value: '${bandwidth.toStringAsFixed(2)} MB/s',
                color: const Color(0xFF2196F3),
                icon: Icons.speed,
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: 'Avg Swap',
                value: '${avgSwap.toStringAsFixed(1)} ms',
                color: const Color(0xFFFF9800),
                icon: Icons.swap_horiz,
              ),
            ),
            Expanded(
              child: _MetricCard(
                label: 'Prediction',
                value: '${prediction.toStringAsFixed(1)}%',
                color: const Color(0xFFE040FB),
                icon: Icons.psychology,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pool Entries
// ---------------------------------------------------------------------------

class _PoolEntriesRow extends StatelessWidget {
  const _PoolEntriesRow({
    required this.entries,
    required this.maxConcurrent,
  });

  final List<_EntryModel> entries;
  final int maxConcurrent;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Container(
          height: 100,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              'No active entries yet. Start scrolling in the Feed tab.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 13,
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 120,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: entries.length,
        itemBuilder: (context, i) {
          final entry = entries[i];
          return _EntryCard(entry: entry);
        },
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry});

  final _EntryModel entry;

  @override
  Widget build(BuildContext context) {
    final stateColor = _colorForState(entry.state);

    return Container(
      width: 140,
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: entry.isPrimary
              ? const Color(0xFF7C4DFF)
              : stateColor.withValues(alpha: 0.3),
          width: entry.isPrimary ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Entry #${entry.entryId}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (entry.isPrimary)
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF7C4DFF),
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: stateColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              entry.state,
              style: TextStyle(
                color: stateColor,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Text(
            entry.assignedIndex != null
                ? 'Video idx: ${entry.assignedIndex}'
                : 'Idle',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Color _colorForState(String state) {
    return switch (state) {
      'PLAYING' => const Color(0xFF7C4DFF),
      'READY' => const Color(0xFF4CAF50),
      'PREPARING' => const Color(0xFF2196F3),
      'BUFFERING' => const Color(0xFFFF9800),
      'PAUSED' => const Color(0xFF9E9E9E),
      'ERROR' => const Color(0xFFF44336),
      'IDLE' => const Color(0xFF616161),
      _ => const Color(0xFF616161),
    };
  }
}

// ---------------------------------------------------------------------------
// Device Status
// ---------------------------------------------------------------------------

class _DeviceStatusRow extends StatelessWidget {
  const _DeviceStatusRow({
    required this.thermalLevel,
    required this.memoryPressure,
    required this.effectiveMaxConcurrent,
  });

  final ThermalLevel thermalLevel;
  final MemoryPressureLevel memoryPressure;
  final int effectiveMaxConcurrent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: _StatusItem(
                icon: Icons.thermostat,
                label: 'Thermal',
                value: thermalLevel.name.toUpperCase(),
                color: _thermalColor(thermalLevel),
              ),
            ),
            Container(
              width: 1,
              height: 36,
              color: const Color(0xFF2A2A3E),
            ),
            Expanded(
              child: _StatusItem(
                icon: Icons.memory,
                label: 'Memory',
                value: memoryPressure.name.toUpperCase(),
                color: _memoryColor(memoryPressure),
              ),
            ),
            Container(
              width: 1,
              height: 36,
              color: const Color(0xFF2A2A3E),
            ),
            Expanded(
              child: _StatusItem(
                icon: Icons.tune,
                label: 'Max Conc.',
                value: '$effectiveMaxConcurrent',
                color: const Color(0xFF2196F3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _thermalColor(ThermalLevel level) {
    return switch (level) {
      ThermalLevel.nominal => const Color(0xFF4CAF50),
      ThermalLevel.fair => const Color(0xFFFFEB3B),
      ThermalLevel.serious => const Color(0xFFFF9800),
      ThermalLevel.critical => const Color(0xFFF44336),
    };
  }

  Color _memoryColor(MemoryPressureLevel level) {
    return switch (level) {
      MemoryPressureLevel.normal => const Color(0xFF4CAF50),
      MemoryPressureLevel.warning => const Color(0xFFFFEB3B),
      MemoryPressureLevel.critical => const Color(0xFFFF9800),
      MemoryPressureLevel.terminal => const Color(0xFFF44336),
    };
  }
}

class _StatusItem extends StatelessWidget {
  const _StatusItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Event Stream
// ---------------------------------------------------------------------------

class _EventStreamPanel extends StatelessWidget {
  const _EventStreamPanel({required this.events});

  final List<_EventRecord> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Container(
          height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              'Waiting for events...',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 13,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 300),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF1A1A2E),
            width: 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: events.length.clamp(0, 20),
            itemBuilder: (_, i) {
              final event = events[i];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text(
                  event.label,
                  style: TextStyle(
                    color: event.color,
                    fontSize: 11,
                    fontFamily: 'monospace',
                    height: 1.4,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section Header
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.6),
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class _EntryModel {
  _EntryModel({
    required this.entryId,
    required this.assignedIndex,
    required this.state,
  });

  final int entryId;
  final int? assignedIndex;
  final String state;
  bool isPrimary = false;
}

class _EventRecord {
  const _EventRecord({required this.label, required this.color});

  final String label;
  final Color color;

  factory _EventRecord.fromEvent(PoolEvent event) {
    final (label, color) = switch (event) {
      SwapEvent e => (
          'SWAP  #${e.entryId} -> idx ${e.toIndex} (${e.durationMs}ms${e.isWarmStart ? ", warm" : ""})',
          const Color(0xFF4CAF50),
        ),
      ReconcileEvent e => (
          'RECON p=${e.primaryIndex} play=${e.playCount} pre=${e.preloadCount} rel=${e.releaseCount}',
          const Color(0xFF81C784),
        ),
      ThrottleEvent e => (
          'THROT thermal=${e.thermalLevel.name} mem=${e.memoryPressure.name} max=${e.effectiveMaxConcurrent}',
          const Color(0xFFFFEB3B),
        ),
      CacheEvent e => (
          'CACHE ${e.action.name} ${e.cacheKey.length > 20 ? '${e.cacheKey.substring(0, 20)}...' : e.cacheKey}',
          const Color(0xFF2196F3),
        ),
      BandwidthSampleEvent e => (
          'BW    ${(e.estimatedBytesPerSec / 1024).toStringAsFixed(0)} KB/s (${e.durationMs}ms)',
          const Color(0xFF29B6F6),
        ),
      PredictionEvent e => (
          'PRED  idx=${e.predictedIndex} conf=${e.confidence.toStringAsFixed(2)}${e.actualIndex != null ? " actual=${e.actualIndex}" : ""}',
          const Color(0xFFE040FB),
        ),
      LifecycleEvent e => (
          'LIFE  #${e.entryId} ${e.fromState.name}->${e.toState.name}',
          const Color(0xFF80CBC4),
        ),
      EmergencyFlushEvent e => (
          'FLUSH survivor=${e.survivorEntryId} disposed=${e.disposedCount}',
          const Color(0xFFFF5722),
        ),
      ErrorEvent e => (
          'ERR   [${e.code}] ${e.message}',
          const Color(0xFFF44336),
        ),
      TokenEvent e => (
          'TOKEN ${e.runtimeType} pool=${e.poolId}',
          const Color(0xFF9E9E9E),
        ),
    };

    return _EventRecord(label: label, color: color);
  }
}
