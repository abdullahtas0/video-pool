import 'package:flutter/widgets.dart';

import '../../platform/platform_interface.dart';

/// Manages system audio focus and app lifecycle pause/resume behavior.
///
/// Requests/releases system audio focus via [VideoPoolPlatform] (which maps
/// to AVAudioSession on iOS and AudioManager on Android). Also observes
/// [WidgetsBindingObserver] to auto-pause video when the app goes to
/// the background and auto-resume when it returns.
class AudioFocusManager with WidgetsBindingObserver {
  /// Creates an [AudioFocusManager] backed by the given [platform].
  AudioFocusManager({required VideoPoolPlatform platform})
      : _platform = platform;

  final VideoPoolPlatform _platform;

  /// Whether this manager currently holds system audio focus.
  bool _hasFocus = false;

  /// Whether video was playing before the app went to the background.
  bool _wasPlayingBeforeBackground = false;

  /// Callback invoked when the manager decides playback should pause
  /// (e.g. app backgrounded).
  VoidCallback? _onShouldPause;

  /// Callback invoked when the manager decides playback should resume
  /// (e.g. app foregrounded after being backgrounded while playing).
  VoidCallback? _onShouldResume;

  /// Whether this manager has been disposed.
  bool _disposed = false;

  /// Whether this manager currently holds audio focus.
  bool get hasFocus => _hasFocus;

  /// Request system audio focus (pauses Spotify, other media apps, etc.).
  ///
  /// On iOS this configures AVAudioSession for playback.
  /// On Android this calls AudioManager.requestAudioFocus.
  Future<void> requestFocus() async {
    if (_disposed) return;
    _hasFocus = await _platform.requestAudioFocus();
  }

  /// Release system audio focus.
  Future<void> releaseFocus() async {
    if (_disposed) return;
    if (_hasFocus) {
      await _platform.releaseAudioFocus();
      _hasFocus = false;
    }
  }

  /// Register callbacks for pause/resume decisions.
  ///
  /// [onPause] is called when the manager decides playback should pause.
  /// [onResume] is called when playback should resume.
  void setCallbacks({VoidCallback? onPause, VoidCallback? onResume}) {
    _onShouldPause = onPause;
    _onShouldResume = onResume;
  }

  /// Start observing app lifecycle changes.
  ///
  /// Call this once after construction. The manager will register itself
  /// as a [WidgetsBindingObserver].
  void startObserving() {
    WidgetsBinding.instance.addObserver(this);
  }

  /// Called when the app lifecycle state changes.
  ///
  /// When the app goes to [AppLifecycleState.paused] (backgrounded),
  /// the manager calls [_onShouldPause] and remembers that playback was active.
  /// When the app returns to [AppLifecycleState.resumed], if playback was
  /// active before backgrounding, it calls [_onShouldResume].
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;

    switch (state) {
      case AppLifecycleState.paused:
        // Only pause on full background (not inactive, which fires for
        // system dialogs, app switcher, etc. on iOS).
        if (_hasFocus && !_wasPlayingBeforeBackground) {
          _wasPlayingBeforeBackground = true;
          _onShouldPause?.call();
        }
      case AppLifecycleState.resumed:
        if (_wasPlayingBeforeBackground) {
          _wasPlayingBeforeBackground = false;
          _onShouldResume?.call();
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  /// Dispose this manager.
  ///
  /// Releases audio focus and removes the lifecycle observer.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    await releaseFocus();
    _onShouldPause = null;
    _onShouldResume = null;
  }
}
