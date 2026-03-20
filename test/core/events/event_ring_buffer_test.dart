import 'package:flutter_test/flutter_test.dart';
import 'package:video_pool/src/core/events/event_ring_buffer.dart';
import 'package:video_pool/src/core/events/pool_event.dart';

ErrorEvent _evt(String code) =>
    ErrorEvent(code: code, message: '', fatal: false);

void main() {
  group('EventRingBuffer', () {
    test('starts empty', () {
      final buffer = EventRingBuffer(capacity: 5);
      expect(buffer.length, 0);
      expect(buffer.snapshot(), isEmpty);
    });

    test('adds events up to capacity', () {
      final buffer = EventRingBuffer(capacity: 3);
      buffer.add(_evt('A'));
      buffer.add(_evt('B'));
      buffer.add(_evt('C'));

      expect(buffer.length, 3);
      final snap = buffer.snapshot();
      expect(snap.length, 3);
      expect((snap[0] as ErrorEvent).code, 'A');
      expect((snap[1] as ErrorEvent).code, 'B');
      expect((snap[2] as ErrorEvent).code, 'C');
    });

    test('overwrites oldest when full', () {
      final buffer = EventRingBuffer(capacity: 3);
      buffer.add(_evt('A'));
      buffer.add(_evt('B'));
      buffer.add(_evt('C'));
      buffer.add(_evt('D'));

      expect(buffer.length, 3);
      final snap = buffer.snapshot();
      expect(snap.length, 3);
      expect((snap[0] as ErrorEvent).code, 'B');
      expect((snap[1] as ErrorEvent).code, 'C');
      expect((snap[2] as ErrorEvent).code, 'D');
    });

    test('snapshot returns a copy — mutations do not affect buffer', () {
      final buffer = EventRingBuffer(capacity: 5);
      buffer.add(_evt('A'));
      buffer.add(_evt('B'));

      final snap1 = buffer.snapshot();

      buffer.add(_evt('C'));

      final snap2 = buffer.snapshot();

      expect(snap1.length, 2);
      expect(snap2.length, 3);
      expect((snap1[0] as ErrorEvent).code, 'A');
      expect((snap1[1] as ErrorEvent).code, 'B');
    });

    test('handles wrap-around correctly after many adds', () {
      final buffer = EventRingBuffer(capacity: 3);
      for (var i = 0; i < 10; i++) {
        buffer.add(_evt('E$i'));
      }

      expect(buffer.length, 3);
      final snap = buffer.snapshot();
      expect(snap.length, 3);
      expect((snap[0] as ErrorEvent).code, 'E7');
      expect((snap[1] as ErrorEvent).code, 'E8');
      expect((snap[2] as ErrorEvent).code, 'E9');
    });

    test('clear resets buffer', () {
      final buffer = EventRingBuffer(capacity: 5);
      buffer.add(_evt('A'));
      buffer.add(_evt('B'));
      buffer.add(_evt('C'));

      buffer.clear();

      expect(buffer.length, 0);
      expect(buffer.snapshot(), isEmpty);
    });
  });
}
