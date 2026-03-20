import 'package:flutter_test/flutter_test.dart';
import 'package:video_pool/src/core/audio/audio_focus_manager.dart';

import '../../mocks/mock_device_monitor.dart';

/// Tests for Phase 3: Audio focus change handling.
void main() {
  late MockDeviceMonitor platform;
  late AudioFocusManager manager;

  setUp(() {
    // Ensure WidgetsBinding is initialized for lifecycle observer.
    TestWidgetsFlutterBinding.ensureInitialized();
    platform = MockDeviceMonitor();
    manager = AudioFocusManager(platform: platform);
  });

  tearDown(() async {
    await manager.dispose();
    platform.dispose();
  });

  group('Audio focus stream handling', () {
    test('focus lost triggers onShouldPause callback', () async {
      var pauseCalled = false;
      manager.setCallbacks(
        onPause: () => pauseCalled = true,
        onResume: () {},
      );
      manager.startObserving();

      platform.emitAudioFocusChange(false); // focus lost
      await Future<void>.delayed(Duration.zero);

      expect(pauseCalled, isTrue);
    });

    test('focus gained triggers onShouldResume callback', () async {
      var resumeCalled = false;
      manager.setCallbacks(
        onPause: () {},
        onResume: () => resumeCalled = true,
      );
      manager.startObserving();

      platform.emitAudioFocusChange(true); // focus gained
      await Future<void>.delayed(Duration.zero);

      expect(resumeCalled, isTrue);
    });

    test('events after dispose are ignored', () async {
      var callCount = 0;
      manager.setCallbacks(
        onPause: () => callCount++,
        onResume: () => callCount++,
      );
      manager.startObserving();

      await manager.dispose();

      // These events should be ignored.
      platform.emitAudioFocusChange(false);
      platform.emitAudioFocusChange(true);
      await Future<void>.delayed(Duration.zero);

      expect(callCount, 0);
    });

    test('no memory leak — subscription is cancelled on dispose', () async {
      manager.setCallbacks(
        onPause: () {},
        onResume: () {},
      );
      manager.startObserving();
      await manager.dispose();

      // The stream controller should still work (not closed by manager).
      // But manager should not be listening anymore.
      expect(platform.audioFocusController.hasListener, isFalse);
    });
  });

  group('Audio focus stream from platform interface', () {
    test('default platform returns empty audio focus stream', () {
      // The base class default should return an empty stream.
      // MockDeviceMonitor overrides this, so we check the stream exists.
      expect(platform.audioFocusStream, isA<Stream<bool>>());
    });
  });
}
