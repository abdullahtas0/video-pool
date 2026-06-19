import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:media_kit_video/media_kit_video.dart' as media_kit_video;

import '../models/video_source.dart';
import 'player_adapter.dart';
import 'player_state.dart';

/// A [PlayerAdapter] implementation backed by media_kit.
///
/// Wraps [Player] and [media_kit_video.VideoController] to provide the
/// pool-friendly adapter interface. The key capability is [swapSource],
/// which replaces the loaded media while preserving the player wrapper and
/// texture surface — enabling fast instance reuse during feed scrolling.
///
/// To facilitate testing, the [Player] can be injected via the constructor.
class MediaKitAdapter implements PlayerAdapter {
  /// Creates a new [MediaKitAdapter].
  ///
  /// If [player] is provided it will be used directly (useful for testing).
  /// Otherwise a new [Player] is created internally using [configuration].
  ///
  /// When [fastStartHls] is true (the default), the adapter applies a set of
  /// libmpv properties that reduce HLS (`.m3u8`) startup latency: it begins
  /// at the lowest variant bitrate so the first segment downloads quickly and
  /// shrinks the initial read-ahead window. ABR still adapts upward during
  /// playback. Set this to false to keep media_kit's default behavior.
  MediaKitAdapter({
    Player? player,
    PlayerConfiguration configuration = const PlayerConfiguration(),
    bool fastStartHls = true,
  })  : _player = player ?? Player(configuration: configuration),
        _stateNotifier = ValueNotifier<PlayerState>(const PlayerState()) {
    _controller = media_kit_video.VideoController(_player);
    _setupListeners();
    if (fastStartHls) {
      // Fire-and-forget — properties are best-effort and may be unsupported
      // on some platforms.
      _applyNetworkTuning();
    }
  }

  final Player _player;
  late final media_kit_video.VideoController _controller;
  final ValueNotifier<PlayerState> _stateNotifier;

  final List<StreamSubscription<dynamic>> _subscriptions = [];

  // Cached dimensions for memory estimation.
  int _videoWidth = 0;
  int _videoHeight = 0;

  // Track position/duration locally for the getters.
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  /// Default memory estimate when video dimensions are unknown.
  ///
  /// Assumes 1920x1080 @ RGBA (4 bytes/pixel) with 3 frame buffers.
  static const int _defaultMemoryEstimate = 1920 * 1080 * 4 * 3; // ~24 MB

  // ──────────────────────────── PlayerAdapter ────────────────────────────

  @override
  Future<void> swapSource(VideoSource source) async {
    // CRITICAL: Stop current playback completely before loading new media
    // to prevent audio from the previous video bleeding through.
    // media_kit's Player.open() starts a new audio decoder, but the old
    // audio track may not be destroyed if we only pause().
    try {
      await _player.setVolume(0); // Mute first to prevent any audio bleed
      await _player.pause();      // Then pause playback
    } catch (_) {
      // Player may not have media loaded yet — ignore.
    }

    // Ghost-frame prevention: immediately reset state before opening the
    // new source so that any UI bound to [stateNotifier] stops rendering
    // the previous video's frames.
    _stateNotifier.value = PlayerState(
      phase: PlaybackPhase.idle,
      currentSource: source,
    );

    final mediaUri = _mediaUriForSource(source);
    await _player.open(Media(mediaUri), play: false);

    // Restore volume after new media is loaded.
    await _player.setVolume(100);
  }

  @override
  Future<void> prepare() async {
    _stateNotifier.value = _stateNotifier.value.copyWith(
      phase: PlaybackPhase.preparing,
    );

    // Seeking to the beginning triggers the decoder to produce the first
    // frame without starting continuous playback.
    await _player.seek(Duration.zero);
  }

  @override
  Future<void> play() async {
    await _player.play();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
  }

  @override
  Future<void> dispose() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();

    await _player.dispose();

    _stateNotifier.value = _stateNotifier.value.copyWith(
      phase: PlaybackPhase.disposed,
    );
  }

  @override
  bool get isReusable {
    final phase = _stateNotifier.value.phase;
    return phase == PlaybackPhase.idle || phase == PlaybackPhase.paused;
  }

  @override
  ValueNotifier<PlayerState> get stateNotifier => _stateNotifier;

  @override
  int get estimatedMemoryBytes {
    if (_videoWidth > 0 && _videoHeight > 0) {
      // RGBA (4 bytes/pixel) * 3 frame buffers
      return _videoWidth * _videoHeight * 4 * 3;
    }
    return _defaultMemoryEstimate;
  }

  /// Cached video widget — must not be recreated on every build.
  late final Widget _videoWidget = media_kit_video.Video(controller: _controller);

  @override
  Widget get videoWidget => _videoWidget;

  @override
  Duration get position => _position;

  @override
  Duration get duration => _duration;

  @override
  Future<void> seekTo(Duration position) async {
    await _player.seek(position);
  }

  @override
  Future<void> setVolume(double volume) async {
    // media_kit uses 0–100 scale.
    await _player.setVolume(volume * 100.0);
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _player.setRate(speed);
  }

  @override
  Future<void> setLooping(bool loop) async {
    await _player.setPlaylistMode(
      loop ? PlaylistMode.single : PlaylistMode.none,
    );
  }

  // ──────────────────────────── Internals ────────────────────────────────

  /// Apply libmpv tuning that reduces HLS / network startup latency.
  ///
  /// These are best-effort: on platforms where `_player.platform` is not a
  /// [NativePlayer] (or a property is unknown), the call is silently ignored.
  ///
  /// The dominant cost of starting an HLS stream is the chain of round-trips
  /// (master playlist → media playlist → first segment) plus, by default,
  /// mpv probing every variant to pick a bitrate. Starting at the lowest
  /// rendition lets the first segment arrive fast; ABR then adapts upward.
  Future<void> _applyNetworkTuning() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    try {
      // Begin at the lowest HLS variant so the first segment is small and
      // playback starts quickly. ABR still scales up during playback.
      await platform.setProperty('hls-bitrate', 'min');
      // Decode the first frame before filling a large read-ahead buffer.
      await platform.setProperty('cache', 'yes');
      await platform.setProperty('cache-secs', '10');
      await platform.setProperty('demuxer-readahead-secs', '5');
      // Fail fast on stalled segment requests instead of hanging the feed.
      await platform.setProperty('network-timeout', '10');
    } catch (_) {
      // Property unsupported on this platform/build — ignore.
    }
  }

  /// Resolve the URI string that media_kit should open for [source].
  String _mediaUriForSource(VideoSource source) {
    switch (source.type) {
      case VideoSourceType.file:
        return source.url;
      case VideoSourceType.asset:
        return 'asset://${source.url}';
      case VideoSourceType.network:
        return source.url;
    }
  }

  /// Subscribe to media_kit player streams and map them to [PlayerState].
  void _setupListeners() {
    _subscriptions.add(
      _player.stream.playing.listen((playing) {
        if (playing) {
          _stateNotifier.value = _stateNotifier.value.copyWith(
            phase: PlaybackPhase.playing,
          );
        } else {
          final current = _stateNotifier.value.phase;
          // Only transition to paused if we were previously playing.
          if (current == PlaybackPhase.playing) {
            _stateNotifier.value = _stateNotifier.value.copyWith(
              phase: PlaybackPhase.paused,
            );
          }
        }
      }),
    );

    _subscriptions.add(
      _player.stream.buffering.listen((isBuffering) {
        if (isBuffering) {
          _stateNotifier.value = _stateNotifier.value.copyWith(
            phase: PlaybackPhase.buffering,
          );
        } else {
          final current = _stateNotifier.value.phase;
          if (current == PlaybackPhase.buffering) {
            // Transition back to playing or ready depending on prior state.
            _stateNotifier.value = _stateNotifier.value.copyWith(
              phase: PlaybackPhase.playing,
            );
          }
        }
      }),
    );

    _subscriptions.add(
      _player.stream.error.listen((error) {
        _stateNotifier.value = _stateNotifier.value.copyWith(
          phase: PlaybackPhase.error,
          errorMessage: error,
        );
      }),
    );

    _subscriptions.add(
      _player.stream.position.listen((pos) {
        _position = pos;
        _stateNotifier.value = _stateNotifier.value.copyWith(
          position: pos,
        );
      }),
    );

    _subscriptions.add(
      _player.stream.duration.listen((dur) {
        _duration = dur;
        _stateNotifier.value = _stateNotifier.value.copyWith(
          duration: dur,
        );
      }),
    );

    _subscriptions.add(
      _player.stream.width.listen((width) {
        if (width != null) _videoWidth = width;
      }),
    );

    _subscriptions.add(
      _player.stream.height.listen((height) {
        if (height != null) _videoHeight = height;
      }),
    );

    _subscriptions.add(
      _player.stream.buffer.listen((buffer) {
        final dur = _duration;
        if (dur.inMilliseconds > 0) {
          final fraction =
              (buffer.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
          _stateNotifier.value = _stateNotifier.value.copyWith(
            bufferedFraction: fraction,
          );
        }
      }),
    );

    // When the player completes loading and is ready (first frame decoded),
    // transition from preparing → ready.
    _subscriptions.add(
      _player.stream.completed.listen((completed) {
        if (completed) {
          final current = _stateNotifier.value.phase;
          if (current == PlaybackPhase.playing) {
            _stateNotifier.value = _stateNotifier.value.copyWith(
              phase: PlaybackPhase.paused,
            );
          }
        }
      }),
    );
  }
}
