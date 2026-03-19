import 'package:flutter_test/flutter_test.dart';
import 'package:video_pool/video_pool.dart';

void main() {
  group('LruCache', () {
    test('stores and retrieves values', () {
      final cache = LruCache<String, int>(maxSize: 3);
      cache.put('a', 1);
      cache.put('b', 2);

      expect(cache.get('a'), 1);
      expect(cache.get('b'), 2);
      expect(cache.get('c'), isNull);
    });

    test('returns null for missing keys', () {
      final cache = LruCache<String, int>(maxSize: 3);
      expect(cache.get('missing'), isNull);
    });

    test('evicts least recently used entry when full', () {
      final cache = LruCache<String, int>(maxSize: 2);
      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('c', 3); // Should evict 'a'

      expect(cache.get('a'), isNull);
      expect(cache.get('b'), 2);
      expect(cache.get('c'), 3);
      expect(cache.length, 2);
    });

    test('accessing an entry promotes it to most recent', () {
      final cache = LruCache<String, int>(maxSize: 2);
      cache.put('a', 1);
      cache.put('b', 2);

      // Access 'a' to promote it.
      cache.get('a');

      // Now 'b' is the least recently used.
      cache.put('c', 3); // Should evict 'b', not 'a'.

      expect(cache.get('a'), 1);
      expect(cache.get('b'), isNull);
      expect(cache.get('c'), 3);
    });

    test('updating an existing key promotes it', () {
      final cache = LruCache<String, int>(maxSize: 2);
      cache.put('a', 1);
      cache.put('b', 2);

      // Update 'a' — promotes it.
      cache.put('a', 10);

      // Now 'b' is least recent.
      cache.put('c', 3); // Should evict 'b'.

      expect(cache.get('a'), 10);
      expect(cache.get('b'), isNull);
      expect(cache.get('c'), 3);
    });

    test('calls onEvict when an entry is evicted', () {
      final evicted = <String, int>{};
      final cache = LruCache<String, int>(
        maxSize: 2,
        onEvict: (key, value) => evicted[key] = value,
      );

      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('c', 3); // Evicts 'a'

      expect(evicted, {'a': 1});
    });

    test('does not call onEvict on explicit remove', () {
      var evictCalled = false;
      final cache = LruCache<String, int>(
        maxSize: 3,
        onEvict: (_, __) => evictCalled = true,
      );

      cache.put('a', 1);
      cache.remove('a');

      expect(evictCalled, isFalse);
    });

    test('remove returns the value or null', () {
      final cache = LruCache<String, int>(maxSize: 3);
      cache.put('a', 1);

      expect(cache.remove('a'), 1);
      expect(cache.remove('a'), isNull);
    });

    test('clear empties the cache', () {
      final cache = LruCache<String, int>(maxSize: 3);
      cache.put('a', 1);
      cache.put('b', 2);

      cache.clear();

      expect(cache.length, 0);
      expect(cache.get('a'), isNull);
    });

    test('containsKey works without promoting', () {
      final cache = LruCache<String, int>(maxSize: 2);
      cache.put('a', 1);
      cache.put('b', 2);

      // containsKey should not promote 'a'.
      expect(cache.containsKey('a'), isTrue);
      expect(cache.containsKey('z'), isFalse);

      // 'a' should still be the oldest since containsKey doesn't promote.
      cache.put('c', 3); // Should evict 'a'.
      expect(cache.get('a'), isNull);
    });

    test('keys, values, and entries iterate in LRU order', () {
      final cache = LruCache<String, int>(maxSize: 3);
      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('c', 3);

      expect(cache.keys.toList(), ['a', 'b', 'c']);
      expect(cache.values.toList(), [1, 2, 3]);

      // Access 'a' to promote it.
      cache.get('a');
      expect(cache.keys.toList(), ['b', 'c', 'a']);
    });

    test('maxSize of 1 works correctly', () {
      final cache = LruCache<String, int>(maxSize: 1);
      cache.put('a', 1);
      cache.put('b', 2); // Evicts 'a'

      expect(cache.get('a'), isNull);
      expect(cache.get('b'), 2);
      expect(cache.length, 1);
    });

    test('multiple evictions in sequence', () {
      final evicted = <String>[];
      final cache = LruCache<String, int>(
        maxSize: 2,
        onEvict: (key, _) => evicted.add(key),
      );

      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('c', 3); // Evicts 'a'
      cache.put('d', 4); // Evicts 'b'

      expect(evicted, ['a', 'b']);
      expect(cache.length, 2);
    });
  });
}
