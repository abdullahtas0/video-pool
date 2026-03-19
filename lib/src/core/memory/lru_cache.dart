import 'dart:collection';

/// A callback invoked when an entry is evicted from the cache.
typedef EvictionCallback<K, V> = void Function(K key, V value);

/// A generic Least Recently Used (LRU) cache.
///
/// When the cache exceeds [maxSize], the least recently accessed entry is
/// evicted. Access via [get] or [put] promotes an entry to most-recent.
///
/// This is used by the video pool for instance reuse: the most recently
/// scrolled-past players stay in cache, while distant ones are evicted.
/// LRU is ideal because feed scrolling is linear — recency approximates
/// spatial proximity.
class LruCache<K, V> {
  /// Creates an LRU cache with the given [maxSize].
  ///
  /// [onEvict] is called whenever an entry is removed due to capacity limits.
  LruCache({
    required this.maxSize,
    this.onEvict,
  }) : assert(maxSize > 0, 'maxSize must be positive');

  /// Maximum number of entries this cache will hold.
  final int maxSize;

  /// Optional callback invoked when an entry is evicted.
  final EvictionCallback<K, V>? onEvict;

  final LinkedHashMap<K, V> _map = LinkedHashMap<K, V>();

  /// The number of entries currently in the cache.
  int get length => _map.length;

  /// All keys in the cache, ordered from least to most recently used.
  Iterable<K> get keys => _map.keys;

  /// All values in the cache, ordered from least to most recently used.
  Iterable<V> get values => _map.values;

  /// All entries in the cache, ordered from least to most recently used.
  Iterable<MapEntry<K, V>> get entries => _map.entries;

  /// Returns whether the cache contains the given [key].
  ///
  /// This does **not** promote the entry (no side effects).
  bool containsKey(K key) => _map.containsKey(key);

  /// Retrieves the value for [key], or `null` if not present.
  ///
  /// Accessing an entry promotes it to most-recently-used.
  V? get(K key) {
    final value = _map.remove(key);
    if (value != null) {
      _map[key] = value;
    }
    return value;
  }

  /// Inserts or updates [key] with [value].
  ///
  /// If the cache is full, the least recently used entry is evicted first.
  /// If [key] already exists, it is promoted to most-recently-used.
  void put(K key, V value) {
    // Remove existing entry so re-insertion places it at the end (most recent).
    final existing = _map.remove(key);
    if (existing != null) {
      // Key already existed — just update the value, no eviction needed.
      _map[key] = value;
      return;
    }

    // Evict the oldest entry if at capacity.
    if (_map.length >= maxSize) {
      final oldestKey = _map.keys.first;
      final oldestValue = _map.remove(oldestKey) as V;
      onEvict?.call(oldestKey, oldestValue);
    }

    _map[key] = value;
  }

  /// Removes the entry for [key] and returns its value, or `null`.
  ///
  /// This does **not** trigger the [onEvict] callback, since the removal
  /// is explicit rather than due to capacity pressure.
  V? remove(K key) => _map.remove(key);

  /// Removes all entries from the cache.
  ///
  /// This does **not** trigger [onEvict] for any entries.
  void clear() => _map.clear();
}
