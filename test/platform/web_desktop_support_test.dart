import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_pool/video_pool.dart';

/// A platform whose audio-focus calls throw, simulating the
/// `MissingPluginException` raised on web/desktop where no native
/// implementation is registered.
class _ThrowingFocusPlatform extends NoOpVideoPoolPlatform {
  const _ThrowingFocusPlatform();

  @override
  Future<bool> requestAudioFocus() async =>
      throw MissingPluginException('no audio focus impl');

  @override
  Future<void> releaseAudioFocus() async =>
      throw MissingPluginException('no audio focus impl');
}

void main() {
  // DeviceMonitor's constructor registers a method-call handler, which
  // requires an initialized binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NoOpVideoPoolPlatform', () {
    const platform = NoOpVideoPoolPlatform();

    test('getCapabilities returns benign, non-constraining defaults', () async {
      final caps = await platform.getCapabilities();
      expect(caps.maxHardwareDecoders, 0);
      expect(caps.supportedCodecs, isEmpty);
      expect(caps.totalMemoryBytes, 0);
    });

    test('start/stopMonitoring complete without throwing', () async {
      await expectLater(platform.startMonitoring(), completes);
      await expectLater(platform.stopMonitoring(), completes);
    });

    test('statusStream emits nothing and closes', () async {
      expect(await platform.statusStream.toList(), isEmpty);
    });

    test('requestAudioFocus is treated as granted', () async {
      expect(await platform.requestAudioFocus(), isTrue);
    });

    test('releaseAudioFocus and audioFocusStream are inert', () async {
      await expectLater(platform.releaseAudioFocus(), completes);
      expect(await platform.audioFocusStream.toList(), isEmpty);
    });
  });

  group('defaultVideoPoolPlatform', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('uses native DeviceMonitor on Android and iOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(defaultVideoPoolPlatform(), isA<DeviceMonitor>());

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(defaultVideoPoolPlatform(), isA<DeviceMonitor>());
    });

    test('falls back to NoOp on desktop platforms', () {
      for (final p in const [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        debugDefaultTargetPlatformOverride = p;
        expect(
          defaultVideoPoolPlatform(),
          isA<NoOpVideoPoolPlatform>(),
          reason: 'expected NoOp on $p',
        );
      }
    });
  });

  group('AudioFocusManager hardening', () {
    test('requestFocus treats a throwing platform as granted', () async {
      final manager =
          AudioFocusManager(platform: const _ThrowingFocusPlatform());
      await manager.requestFocus();
      expect(manager.hasFocus, isTrue);
    });

    test('releaseFocus swallows a throwing platform', () async {
      final manager =
          AudioFocusManager(platform: const _ThrowingFocusPlatform());
      await manager.requestFocus();
      await expectLater(manager.releaseFocus(), completes);
      expect(manager.hasFocus, isFalse);
    });
  });
}
