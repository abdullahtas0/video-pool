import 'pool_event.dart';

/// A fixed-size circular buffer for [PoolEvent] objects.
///
/// Once the buffer reaches [capacity], the oldest events are silently
/// overwritten. Use [snapshot] to obtain a chronologically ordered copy
/// of the current contents.
class EventRingBuffer {
  /// Creates a ring buffer that holds at most [capacity] events.
  EventRingBuffer({this.capacity = 1000})
      : _buffer = List<PoolEvent?>.filled(capacity, null);

  /// The maximum number of events this buffer can hold.
  final int capacity;

  final List<PoolEvent?> _buffer;
  int _head = 0;
  int _count = 0;

  /// The number of events currently stored in the buffer.
  int get length => _count;

  /// Appends [event] to the buffer.
  ///
  /// If the buffer is full the oldest event is overwritten.
  void add(PoolEvent event) {
    _buffer[_head] = event;
    _head = (_head + 1) % capacity;
    if (_count < capacity) _count++;
  }

  /// Returns a chronologically ordered copy of all stored events.
  ///
  /// The returned list is a snapshot — subsequent mutations to the buffer
  /// will not affect it. Returns an empty const list when the buffer is empty.
  List<PoolEvent> snapshot() {
    if (_count == 0) return const [];

    final result = <PoolEvent>[];
    final start = _count < capacity ? 0 : _head;
    for (var i = 0; i < _count; i++) {
      result.add(_buffer[(start + i) % capacity]!);
    }
    return result;
  }

  /// Removes all events from the buffer and resets internal pointers.
  void clear() {
    _buffer.fillRange(0, capacity, null);
    _head = 0;
    _count = 0;
  }
}
