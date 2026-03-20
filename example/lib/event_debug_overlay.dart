import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_pool/video_pool.dart';

/// A debug overlay that shows live pool events.
/// Toggle visibility with a floating action button.
class EventDebugOverlay extends StatefulWidget {
  const EventDebugOverlay({super.key, required this.child});
  final Widget child;

  @override
  State<EventDebugOverlay> createState() => _EventDebugOverlayState();
}

class _EventDebugOverlayState extends State<EventDebugOverlay> {
  bool _visible = false;
  final List<String> _events = [];
  StreamSubscription<PoolEvent>? _subscription;
  static const _maxEvents = 15;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscription?.cancel();
    final pool = VideoPoolProvider.maybeOf(context);
    if (pool != null) {
      _subscription = pool.eventStream.listen(_onEvent);
    }
  }

  void _onEvent(PoolEvent event) {
    if (!mounted) return;
    setState(() {
      final label = switch (event) {
        SwapEvent e => 'SWAP #${e.entryId} -> idx ${e.toIndex} (${e.durationMs}ms${e.isWarmStart ? ", warm" : ""})',
        ReconcileEvent e => 'RECONCILE p=${e.primaryIndex} play=${e.playCount} pre=${e.preloadCount} rel=${e.releaseCount}',
        ThrottleEvent e => 'THROTTLE thermal=${e.thermalLevel.name} mem=${e.memoryPressure.name} max=${e.effectiveMaxConcurrent}',
        CacheEvent e => 'CACHE ${e.action.name} ${e.cacheKey.length > 12 ? e.cacheKey.substring(0, 12) : e.cacheKey}...',
        BandwidthSampleEvent e => 'BW ${(e.estimatedBytesPerSec / 1024).toStringAsFixed(0)} KB/s',
        PredictionEvent e => 'PREDICT idx=${e.predictedIndex} conf=${e.confidence.toStringAsFixed(2)}${e.actualIndex != null ? " actual=${e.actualIndex}" : ""}',
        LifecycleEvent e => 'LIFE #${e.entryId} ${e.fromState.name}->${e.toState.name}',
        EmergencyFlushEvent e => 'FLUSH! survivor=${e.survivorEntryId} disposed=${e.disposedCount}',
        ErrorEvent e => 'ERR [${e.code}] ${e.message}',
        TokenEvent e => 'TOKEN ${e.runtimeType} pool=${e.poolId}',
      };
      _events.insert(0, label);
      if (_events.length > _maxEvents) _events.removeLast();
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        // FAB to toggle
        Positioned(
          right: 12,
          bottom: 80,
          child: FloatingActionButton.small(
            heroTag: 'event_debug',
            onPressed: () => setState(() => _visible = !_visible),
            backgroundColor: _visible ? Colors.red.withValues(alpha: 0.8) : Colors.white24,
            child: Icon(_visible ? Icons.close : Icons.bug_report, size: 20),
          ),
        ),
        // Event log
        if (_visible)
          Positioned(
            left: 8,
            right: 8,
            bottom: 130,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 300),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Pool Events', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Text('${_events.length}', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                    ],
                  ),
                  const Divider(color: Colors.white24, height: 8),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      reverse: false,
                      itemCount: _events.length,
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: Text(
                          _events[i],
                          style: TextStyle(
                            color: _events[i].startsWith('ERR') ? Colors.redAccent
                                : _events[i].startsWith('FLUSH') ? Colors.orangeAccent
                                : _events[i].startsWith('THROTTLE') ? Colors.yellowAccent
                                : Colors.greenAccent.withValues(alpha: 0.8),
                            fontSize: 10,
                            fontFamily: 'monospace',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
