import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/foundation.dart' show ValueListenable, kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import '../models/video_source.dart';
import 'player_adapter.dart';
import 'player_state.dart';

/// A [PlayerAdapter] backed by the official
/// [`video_player`](https://pub.dev/packages/video_player) plugin.
///
/// This adapter lets the pool drive any backend that implements the
/// `video_player` platform interface — for example
/// [`fvp`](https://pub.dev/packages/fvp) (call `fvp.registerWith()` in your
/// app to route `video_player` through libmpv), the default native players, or
/// the web implementation — instead of media_kit.
///
/// ## Swap semantics
///
/// `video_player`'s [VideoPlayerController] has **no in-place source swap**: a
/// controller is bound to a single data source. [swapSource] therefore disposes
/// the current controller and creates a fresh one. The Flutter element that
/// hosts the video ([videoWidget]) stays stable across swaps — it rebinds to
/// the new controller via a [ValueListenable] — but the underlying decoder is
/// recreated rather than reused. This is the documented trade-off of using the
/// standard `video_player` interface; media_kit's adapter reuses the decoder
/// pipeline via `swapSource` and remains the lower-latency default.
///
/// To plug in a custom backend or customise controller creation (headers,
/// caching, format hints), pass a [controllerFactory].
class VideoPlayerAdapter implements PlayerAdapter {
  /// Creates a [VideoPlayerAdapter].
  ///
  /// [controllerFactory] builds a [VideoPlayerController] for a given
  /// [VideoSource]. Defaults to [defaultControllerFactory], which maps the
  /// source type to the matching `video_player` constructor. Inject a custom
  /// factory for tests or to control controller options.
  VideoPlayerAdapter({
    VideoPlayerController Function(VideoSource source)? controllerFactory,
  })  : _controllerFactory = controllerFactory ?? defaultControllerFactory,
        _stateNotifier = ValueNotifier<PlayerState>(const PlayerState());

  final VideoPlayerController Function(VideoSource source) _controllerFactory;
  final ValueNotifier<PlayerState> _stateNotifier;

  /// Drives [videoWidget]: holds the controller currently being rendered.
  final ValueNotifier<VideoPlayerController?> _controllerNotifier =
      ValueNotifier<VideoPlayerController?>(null);

  VideoPlayerController? _controller;
  bool _disposed = false;

  /// Default memory estimate when video dimensions are unknown (~24 MB).
  static const int _defaultMemoryEstimate = 1920 * 1080 * 4 * 3;

  /// Maps a [VideoSource] to the matching [VideoPlayerController] constructor.
  ///
  /// File sources are unsupported on web (no filesystem); there the path is
  /// attempted as a network URI as a best effort.
  static VideoPlayerController defaultControllerFactory(VideoSource source) {
    switch (source.type) {
      case VideoSourceType.network:
        return VideoPlayerController.networkUrl(
          Uri.parse(source.url),
          httpHeaders: source.headers,
        );
      case VideoSourceType.asset:
        return VideoPlayerController.asset(source.url);
      case VideoSourceType.file:
        if (kIsWeb) {
          return VideoPlayerController.networkUrl(Uri.parse(source.url));
        }
        return VideoPlayerController.file(File(source.url));
    }
  }

  // ──────────────────────────── PlayerAdapter ────────────────────────────

  @override
  Future<void> swapSource(VideoSource source) async {
    if (_disposed) return;

    // video_player can't swap in place — tear down the old controller (which
    // also stops its audio) and build a fresh one for the new source.
    await _teardownController();

    _stateNotifier.value = PlayerState(
      phase: PlaybackPhase.preparing,
      currentSource: source,
    );

    VideoPlayerController? controller;
    try {
      controller = _controllerFactory(source);
      _controller = controller;
      controller.addListener(_onControllerUpdate);

      await controller.initialize();
      if (_disposed || !identical(_controller, controller)) {
        // Superseded or disposed while initializing — drop this controller.
        controller.removeListener(_onControllerUpdate);
        await controller.dispose();
        return;
      }
      await controller.setVolume(1);
      _controllerNotifier.value = controller;
      _onControllerUpdate();
    } catch (error) {
      controller?.removeListener(_onControllerUpdate);
      if (identical(_controller, controller)) _controller = null;
      _controllerNotifier.value = null;
      // A controller that failed to initialize can hang on dispose() (its
      // internal creation completer never resolves), so release it without
      // awaiting — otherwise a later dispose() would block.
      final broken = controller;
      if (broken != null) {
        unawaited(broken.dispose().catchError((_) {}));
      }
      _stateNotifier.value = _stateNotifier.value.copyWith(
        phase: PlaybackPhase.error,
        errorMessage: '$error',
      );
    }
  }

  @override
  Future<void> prepare() async {
    final controller = _controller;
    if (controller == null) return;
    _stateNotifier.value = _stateNotifier.value.copyWith(
      phase: PlaybackPhase.preparing,
    );
    try {
      await controller.seekTo(Duration.zero);
    } catch (_) {
      // Best-effort — some backends reject seek before play.
    }
    _onControllerUpdate();
  }

  @override
  Future<void> play() async {
    await _controller?.play();
  }

  @override
  Future<void> pause() async {
    await _controller?.pause();
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _teardownController();
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
    final size = _controller?.value.size;
    if (size != null && size.width > 0 && size.height > 0) {
      // RGBA (4 bytes/pixel) * 3 frame buffers.
      return (size.width * size.height * 4 * 3).round();
    }
    return _defaultMemoryEstimate;
  }

  late final Widget _videoWidget =
      _VideoPlayerHost(controllerListenable: _controllerNotifier);

  @override
  Widget get videoWidget => _videoWidget;

  @override
  Duration get position => _controller?.value.position ?? Duration.zero;

  @override
  Duration get duration => _controller?.value.duration ?? Duration.zero;

  @override
  Future<void> seekTo(Duration position) async {
    await _controller?.seekTo(position);
  }

  @override
  Future<void> setVolume(double volume) async {
    await _controller?.setVolume(volume.clamp(0.0, 1.0));
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _controller?.setPlaybackSpeed(speed);
  }

  @override
  Future<void> setLooping(bool loop) async {
    await _controller?.setLooping(loop);
  }

  // ──────────────────────────── Internals ────────────────────────────────

  /// Maps the current [VideoPlayerValue] to a [PlayerState].
  void _onControllerUpdate() {
    final controller = _controller;
    if (controller == null || _disposed) return;
    final value = controller.value;

    final PlaybackPhase phase;
    if (value.hasError) {
      phase = PlaybackPhase.error;
    } else if (!value.isInitialized) {
      phase = PlaybackPhase.preparing;
    } else if (value.isBuffering) {
      phase = PlaybackPhase.buffering;
    } else if (value.isPlaying) {
      phase = PlaybackPhase.playing;
    } else {
      // Initialized but not playing — reusable for the pool.
      phase = PlaybackPhase.paused;
    }

    final duration = value.duration;
    final buffered =
        value.buffered.isNotEmpty ? value.buffered.last.end : Duration.zero;
    final bufferedFraction = duration.inMilliseconds > 0
        ? (buffered.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    _stateNotifier.value = _stateNotifier.value.copyWith(
      phase: phase,
      position: value.position,
      duration: duration,
      bufferedFraction: bufferedFraction,
      errorMessage: value.hasError ? value.errorDescription : null,
      clearErrorMessage: !value.hasError,
    );
  }

  /// Disposes the active controller and detaches it from the render surface.
  Future<void> _teardownController() async {
    final controller = _controller;
    if (controller == null) return;
    controller.removeListener(_onControllerUpdate);
    _controller = null;
    _controllerNotifier.value = null;
    try {
      await controller.pause();
    } catch (_) {
      // Ignore — controller may already be in a terminal state.
    }
    try {
      await controller.dispose();
    } catch (_) {
      // Ignore double-dispose.
    }
  }
}

/// Stable host widget for the video surface.
///
/// Kept as a single cached widget by [VideoPlayerAdapter.videoWidget] so the
/// element stays mounted across source swaps; it rebinds to whichever
/// controller is current via [controllerListenable].
class _VideoPlayerHost extends StatelessWidget {
  const _VideoPlayerHost({required this.controllerListenable});

  final ValueListenable<VideoPlayerController?> controllerListenable;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerController?>(
      valueListenable: controllerListenable,
      builder: (context, controller, _) {
        if (controller == null || !controller.value.isInitialized) {
          return const SizedBox.shrink();
        }
        return VideoPlayer(controller);
      },
    );
  }
}
