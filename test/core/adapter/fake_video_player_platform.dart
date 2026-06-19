import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter/widgets.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// In-memory fake of [VideoPlayerPlatform] for testing [VideoPlayerAdapter]
/// without any native plugin. Each created player gets a broadcast event
/// stream that emits an `initialized` event on first listen, so
/// `VideoPlayerController.initialize()` completes.
class FakeVideoPlayerPlatform extends VideoPlayerPlatform
    with MockPlatformInterfaceMixin {
  /// Ordered log of platform calls, e.g. `create`, `play`, `dispose`.
  final List<String> calls = [];

  /// Size reported in the `initialized` event.
  Size initializedSize = const Size(640, 480);

  /// Duration reported in the `initialized` event.
  Duration initializedDuration = const Duration(seconds: 10);

  /// When true, [create] returns `null` to simulate a creation failure.
  bool failCreate = false;

  int _nextId = 1;
  final Map<int, StreamController<VideoEvent>> _events = {};

  StreamController<VideoEvent> _controllerFor(int id) {
    return _events.putIfAbsent(id, () {
      late StreamController<VideoEvent> controller;
      controller = StreamController<VideoEvent>.broadcast(
        onListen: () {
          controller.add(
            VideoEvent(
              eventType: VideoEventType.initialized,
              duration: initializedDuration,
              size: initializedSize,
            ),
          );
        },
      );
      return controller;
    });
  }

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) async {
    calls.add('create');
    if (failCreate) {
      throw PlatformException(code: 'create_failed', message: 'fake failure');
    }
    final id = _nextId++;
    _controllerFor(id);
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) =>
      _controllerFor(playerId).stream;

  @override
  Future<void> dispose(int playerId) async {
    calls.add('dispose');
    await _events.remove(playerId)?.close();
  }

  @override
  Future<void> play(int playerId) async => calls.add('play');

  @override
  Future<void> pause(int playerId) async => calls.add('pause');

  @override
  Future<void> setLooping(int playerId, bool looping) async =>
      calls.add('setLooping:$looping');

  @override
  Future<void> setVolume(int playerId, double volume) async =>
      calls.add('setVolume:$volume');

  @override
  Future<void> seekTo(int playerId, Duration position) async =>
      calls.add('seekTo:${position.inMilliseconds}');

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async =>
      calls.add('setSpeed:$speed');

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Widget buildView(int playerId) => const SizedBox.shrink();
}
