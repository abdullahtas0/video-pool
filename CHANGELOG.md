# Changelog

All notable changes to this project will be documented in this file.

## 0.5.3

### Documentation & Tooling
- **100% public API documentation** — added dartdoc to the five previously
  undocumented constructors (`PlayerAdapter`, `LifecyclePolicy`, `DecoderBudget`,
  `VideoPoolPlatform`) and made the desktop registrant non-instantiable.
- **README polish** — pub/CI/license badges, a live web-demo link, an honest
  comparison vs. `video_player`/`chewie`/`better_player`/`preload_page_view`,
  and a roadmap.
- **Live web demo** — a GitHub Actions workflow builds the example for the web
  and publishes it to GitHub Pages.
- **CI** — added a workflow that runs `dart format`, `flutter analyze`, and the
  full test suite on every push and pull request.
- Added `CONTRIBUTING.md` and a minimal single-file example
  (`example/lib/minimal_example.dart`).
- Normalized formatting across the codebase (`dart format`). No behavior change.

## 0.5.2

### Example
- **Fixed the example's sample video URLs.** The previous Google
  `gtv-videos-bucket` URLs now return HTTP 403, so the demo could not load any
  video. Replaced them with short, CORS-enabled CC0 clips (Flutter's asset CDN
  and MDN) that play on every platform. Verified live on web: the feed now plays
  real video with no 403/CORS errors.

## 0.5.1

### Platform Declaration
- **Declared web, macOS, Windows, and Linux as supported plugin platforms** so
  pub.dev shows all six platform badges (previously only Android/iOS). Android
  and iOS keep their native plugin classes; web uses a no-op web plugin
  registrant and desktop uses a no-op `dartPluginClass` — no native code is
  needed on those platforms because the device monitor and disk cache already
  fall back to no-ops there. Verified with `pana` (6 / 6 platforms) and by
  building the example for web and macOS.
- Added `flutter_web_plugins` (Flutter SDK) as a dependency for the web
  registrant.

## 0.5.0

### New Features
- **`VideoPlayerAdapter`** — a `PlayerAdapter` backed by the official
  [`video_player`](https://pub.dev/packages/video_player) plugin. Because it
  drives the standard `video_player` platform interface, you can now swap the
  playback backend (e.g. [`fvp`](https://pub.dev/packages/fvp) for libmpv,
  ExoPlayer, or AVPlayer) instead of media_kit — just pass
  `adapterFactory: (_) => VideoPlayerAdapter()`. `MediaKitAdapter` remains the
  default.
  - Maps `video_player`'s `VideoPlayerValue` to the pool's `PlayerState`
    (preparing / playing / buffering / paused / error), exposes a stable video
    surface that rebinds across swaps, and derives the memory estimate from the
    video size.
  - **Swap semantics:** `video_player` has no in-place source swap, so
    `swapSource()` disposes the controller and creates a fresh one (decoder
    recreated, not reused) — the documented trade-off of the standard interface.
  - Hardened against failed initialization: a controller that throws during
    `initialize()` is released without awaiting its (never-completing) dispose,
    so it can't hang the pool.
- Added `video_player` as a dependency. The package still compiles on web
  (`dart:io` use is guarded by `kIsWeb`).

### Testing
- Added `VideoPlayerAdapter` unit tests (state mapping, recreate-on-swap,
  controls, error handling, widget rendering) and an end-to-end integration
  test driving a real `VideoPlayerAdapter` through `VideoPool` via a fake
  platform. 269 tests total.

## 0.4.0

### Web Support
- **The package now compiles and runs on web** via conditional compilation.
  Two web-incompatible code paths were isolated behind `dart.library.io`
  conditional imports with no-op web stubs:
  - `MediaKitAdapter`'s HLS tuning (`NativePlayer.setProperty`, which does not
    exist on media_kit's web player) → `network_tuning.dart` resolves to a
    native impl or a web no-op.
  - `FilePreloadManager` (`dart:io` + `dart:isolate`) and `ThumbnailExtractor`
    (`dart:io` + platform channel) → each resolves to the native impl or an
    inert web stub. The shared `CachedFile` type moved to a pure-Dart
    `file_preload_types.dart`. On web the disk cache reports "not cached" and
    `prefetch` returns `null`, so the pool streams network URLs directly.
- **Verified end-to-end in Chrome**: `flutter build web` succeeds and the app
  runs — the pool initializes, reconciles, and assigns entries with no errors
  or `MissingPluginException`. Desktop (macOS) re-verified for no regression.
- **Example made platform-agnostic**: skips the disk cache on web (`kIsWeb`) and
  uses `defaultVideoPoolPlatform()` so it runs on Android, iOS, web, and desktop.

### Testing
- Added web-stub unit tests (`FilePreloadManager`, `ThumbnailExtractor`, and the
  `applyNetworkTuning` no-op). 255 tests total.

## 0.3.4

### Documentation / Platform Scope Correction
- **Corrected platform support after end-to-end verification.** 0.3.3 described
  web as running; that was premature. Verified results:
  - **macOS / Windows / Linux: supported.** Built and ran the example on macOS —
    the pool reconciles and plays through media_kit with no
    `MissingPluginException` (the no-op device monitor is selected automatically).
  - **Web: not yet compilable.** Two blockers surfaced at build time: media_kit's
    web player has no `NativePlayer.setProperty` (used by the HLS tuning added in
    0.3.2), and the disk cache / thumbnail extractor import `dart:io`. Web support
    now requires conditional compilation and is tracked on the roadmap.
- No library code changed in this release.

## 0.3.3

### Web & Desktop
- **Graceful web and desktop support** — the pool no longer relies on the
  Android/iOS-only native device-monitoring bridge being present. A new
  `NoOpVideoPoolPlatform` is selected automatically (`defaultVideoPoolPlatform()`)
  on web, macOS, Windows, and Linux, so `VideoPoolScope` runs everywhere the
  underlying player (media_kit) plays. Native thermal/memory throttling and
  system audio-focus management remain Android/iOS only; on other platforms the
  pool simply operates at its nominal state.
- **Hardened `AudioFocusManager`** — `requestFocus()`/`releaseFocus()` now
  swallow `MissingPluginException` (treating focus as granted) so a direct call
  on a platform without an audio-focus implementation never throws.
- Exported `NoOpVideoPoolPlatform` and `defaultVideoPoolPlatform()`.

> Note: pub.dev platform badges still list Android/iOS (the package declares
> native plugin platforms for those). Declaring web/desktop as first-class
> plugin platforms is tracked for a future release.

## 0.3.2

### Bug Fixes
- **Restored audio when scrolling back to an already-loaded video** — When an
  entry was demoted from primary to a preload/paused slot it was muted
  (`setVolume(0)`), but volume was only ever restored inside `swapSource`,
  which doesn't run on a cache hit. Revisiting a previously loaded video
  therefore replayed it silently. The pool now restores full volume whenever an
  entry transitions to playing (both in reconciliation and in
  `togglePlayPause`). Added a regression test.

### Performance
- **Faster HLS startup** — `MediaKitAdapter` now accepts a `PlayerConfiguration`
  and applies libmpv network tuning (`hls-bitrate=min`, smaller initial
  read-ahead, network timeout) behind a `fastStartHls` flag (default `true`).
  HLS streams begin at the lowest variant so the first segment arrives quickly;
  ABR still adapts upward during playback.

### iOS / Tooling
- **Swift Package Manager support** — Added `ios/video_pool/Package.swift` and
  moved native sources to `ios/video_pool/Sources/video_pool/` for Flutter's
  SwiftPM migration (3.44+). The CocoaPods podspec is retained and now points at
  the same shared sources, so both build systems keep working.

## 0.3.1

### Bug Fixes
- **Activated predictive scroll engine in widgets** — `VideoFeedView` and `VideoListView` now forward scroll velocity to `pool.onScrollUpdate()` using drag position delta, correctly capturing fling velocity at drag end
- **Activated bandwidth-aware preload in example** — Feed pool now configured with `BandwidthThresholds()`, enabling EMA-based network adaptation
- **Activated cooperative multi-pool in example** — `GlobalDecoderBudget(totalTokens: 4)` shared between Feed and Discover pools
- **Added `decoderBudget` parameter to `VideoPoolScope`** — enables cooperative multi-pool through the widget API without manual pool management

## 0.3.0

### New Features
- **Event-Sourced Observability** — All pool operations emit immutable `PoolEvent` objects via `VideoPool.eventStream`. Sealed class hierarchy with exhaustive switch support: `SwapEvent`, `ReconcileEvent`, `ThrottleEvent`, `CacheEvent`, `LifecycleEvent`, `EmergencyFlushEvent`, `ErrorEvent`, `BandwidthSampleEvent`, `PredictionEvent`, `TokenEvent`
- **MetricsSnapshot** — Lazy-computed metrics from ring buffer: cache hit rate, avg swap latency, throttle count, bandwidth estimate, prediction accuracy. Access via `pool.metrics`
- **Bandwidth Intelligence** — EMA-based bandwidth estimation from prefetch download durations. Network-aware preload: automatically adjusts `preloadCount` and `prefetchBytes` based on measured bandwidth. Configurable thresholds via `BandwidthThresholds` in `VideoPoolConfig`
- **Hysteresis (Schmitt Trigger)** — Prevents flip-flopping at bandwidth threshold boundaries with configurable buffer zone
- **Progressive Download Resume** — Interrupted prefetch downloads resume from where they left off using HTTP Range + If-Range headers. ETag validation prevents serving stale content. Max 3 retries per key
- **Cache Janitor** — Automatically cleans up incomplete cache entries older than 24 hours on app start
- **Predictive Scroll Engine** — Uses Flutter's deterministic scroll physics to predict where the user will stop scrolling. Confidence-based preload: high confidence triggers disk prefetch for target video. Target stabilization prevents redundant predictions
- **Cooperative Multi-Pool** — `DecoderBudget` interface for sharing hardware decoder tokens across multiple `VideoPool` instances. `GlobalDecoderBudget` implementation with token request/release/preemption. Dynamic budget calibration on decoder init failures
- **Auto-Thumbnail Extraction** — Extracts first-frame thumbnails from cached video files using native APIs (iOS `AVAssetImageGenerator`, Android `MediaMetadataRetriever`). FastStart (moov atom) detection. Concurrency-limited extraction queue

### Example App
- Rebuilt as production-grade 3-tab showcase: Feed (TikTok), Discover (Instagram), Insights (live dashboard)
- Feed tab: full-screen video with lifecycle badges, cache status, social buttons, progress bar
- Insights tab: real-time metric cards, pool entry visualization, device status, color-coded event stream
- Tab switching pauses/resumes pool to prevent background audio
- Event debug overlay (toggle with bug icon FAB)

### Testing
- 227 unit tests (up from 132)

## 0.2.1

### Bug Fixes
- **Fixed excessive reconciliation during scroll (BUG-1)** — `VideoPool.onVisibilityChanged()` now uses a threshold state machine that compares playable index sets (indices above `visibilityPlayThreshold`) instead of raw ratio values. Identical threshold states are skipped at near-zero cost, eliminating 17+ redundant reconciliations per scroll frame observed on Redmi Note 8 Pro
- **Fixed `VideoListView` triggering reconciliation every frame** — Added coarse widget-level guard that skips notifications when `primaryIndex` and visible count haven't changed, reducing calls before they reach the pool
- **Fixed `VideoFeedView` blocking mid-swipe preload** — Removed overly restrictive `primaryIndex != _currentPage` guard from `NotificationListener`; pool-level threshold filter now handles deduplication, allowing threshold crossings during page transitions to trigger timely preloads
- **Fixed `Map.of()` copy in `onVisibilityChanged`** — Visibility ratios are now stored by reference instead of copied, eliminating per-frame Map allocation and GC pressure
- **Fixed `resumeLastState()` being silently skipped** — Threshold state is now reset before re-emitting last visibility, ensuring reconciliation runs after app returns from background
- **Fixed `_tryRecoverEntries()` not re-reconciling** — Same threshold reset applied to post-emergency-flush recovery path

### Testing
- 132 unit and widget tests (up from 128)
- New tests: threshold deduplication (skip when unchanged), threshold crossing (trigger on boundary change)

## 0.2.0

### Breaking Changes
- `VideoPoolConfig` now asserts `maxConcurrent <= 10` and `preloadCount < maxConcurrent` (debug mode only; production builds unaffected)

### Bug Fixes
- **Fixed race condition between device events and reconciliation** — Emergency flush now serializes through the `_activeReconciliation` Future chain, preventing disposed-adapter exceptions during concurrent reconciliation
- **Fixed emergency flush with no recovery** — Pool now recreates adapters when memory pressure drops from terminal/critical to normal/warning, re-reconciling with the last known visibility state
- **Fixed FilePreloadManager cache key collision** — Replaced truncated base64 encoding with SHA-256 hash for deterministic, collision-resistant filenames
- **Fixed FilePreloadManager missing HTTP timeout** — Added configurable `connectionTimeoutSeconds` (default: 15s) to prevent hanging downloads
- **Fixed FilePreloadManager missing HTTP status code check** — Only 200/206 responses are accepted; other status codes return an error and clean up partial files
- **Fixed FilePreloadManager evicting files in active use** — Added `lockKey()`/`unlockKey()` API; locked keys are skipped during LRU eviction
- **Fixed FilePreloadManager orphaning partial files on error** — Disk write errors and HTTP failures now delete incomplete files
- **Fixed Android thermal monitoring gap on API 21-28** — Added battery temperature proxy fallback when `PowerManager.currentThermalStatus` is unavailable
- **Fixed audio focus not responding to system interruptions** — Android `OnAudioFocusChangeListener` and iOS `AVAudioSession.interruptionNotification` now send events to Dart; `AudioFocusManager` pauses/resumes playback accordingly
- **Fixed iOS audio resumption after interruption** — Only resumes when system sets `shouldResume` flag, preventing unwanted playback after phone calls
- **Fixed `AudioFocusManager` subscription leak** — Audio focus stream subscription is now cancelled on dispose
- **Fixed `VideoPoolScope.dispose()` async issue** — Async cleanup is now fire-and-forget with error catching, compatible with Flutter's synchronous `State.dispose()`
- **Fixed `swapSource()` documentation** — Updated to accurately describe player wrapper and texture surface reuse (decoder may be re-initialized)

### New Features
- **Disk cache integration** — `VideoPool` now accepts an optional `FilePreloadManager`; cache hits serve local files, misses trigger fire-and-forget prefetch
- **Cold-start manifest** — `FilePreloadManager.loadManifest()` recovers cached files from a previous session via `_manifest.json` sidecar file
- **`ResolutionHint` enum** — `VideoSource.resolutionHint` enables resolution-aware memory estimation (720p ~12MB, 1080p ~24MB, 4K ~96MB)
- **`audioFocusStream`** — New stream on `VideoPoolPlatform` for system audio focus change events (default: empty stream for backward compatibility)
- **Runtime config safety** — `maxConcurrent` is clamped to `[1, 10]` at runtime as a safety net beyond assert-level validation

### Example App
- TikTok example now demonstrates `FilePreloadManager` with disk caching and `ResolutionHint`
- Added `path_provider` dependency for cache directory resolution

### Testing
- 128 unit and widget tests (up from 96)
- New test suites: race condition/recovery, FilePreloadManager enhancements, audio focus handling, VideoSource resolution hints

## 0.1.2

### Improvements
- Fix example app Android v1 embedding build failure — recreated with v2 embedding
- Add INTERNET permission and cleartext traffic support for Android
- Add NSAppTransportSecurity for iOS HTTP video playback
- Fix .gitignore rules that excluded example platform files
- Remove tracked generated files (Pods, .gradle, .symlinks)
- Add `repository`, `issue_tracker`, and `topics` metadata to pubspec
- Shorten package description to meet pub.dev 180 char limit
- Widen `media_kit_video` constraint to support latest version

## 0.1.1

### Bug Fixes
- **Fixed audio overlap on TikTok-style feed scroll** — When scrolling between videos, the previous video's audio could continue playing simultaneously with the new video. This occurred because the `DefaultLifecyclePolicy` excluded preloaded entries from the pause set, allowing a formerly-playing entry to keep its audio running when it transitioned from primary to preloaded state.
  - `DefaultLifecyclePolicy.reconcile()` now correctly adds previously active entries that moved into the preload set to `toPause`
  - `VideoPool._reconcile()` includes a safety net that pauses any entry still in `playing` state during preload cache hits (sets volume to 0 and pauses)

## 0.1.0

Initial release of video_pool — enterprise video orchestration for Flutter.

### Core Engine
- **Controller pooling** with fixed-size player pool and instance reuse via `swapSource()`
- **LifecycleOrchestrator** with pluggable `LifecyclePolicy` strategy pattern
- **MemoryManager** with LRU eviction, pressure-based budget scaling, and emergency flush
- **Serialized reconciliation** with "latest wins" debouncing for fling scroll protection
- **VideoPoolLogger** with configurable log levels (none/error/warning/info/debug)

### Player Adapter
- **MediaKitAdapter** wrapping media_kit with ghost-frame prevention on source swap
- **PlayerAdapter** abstract interface for swappable player backends
- **PlayerState** with `ValueNotifier` for natural `ValueListenableBuilder` integration

### Disk Cache
- **FilePreloadManager** pre-fetching first 2MB of upcoming videos to disk
- Isolate-based downloads (no UI thread blocking)
- 500MB LRU disk cache with automatic eviction
- Stable cache key hashing for cross-restart consistency

### Native Monitoring
- **iOS**: Thermal state via `ProcessInfo`, memory via `os_proc_available_memory()`, audio via `AVAudioSession`
- **Android**: `onTrimMemory` mapping (RUNNING_CRITICAL → terminal flush), `PowerManager.currentThermalStatus`, `AudioManager` focus
- **DeviceCapabilities**: Hardware decoder enumeration, codec support detection

### Audio Focus
- System audio focus management (AVAudioSession / AudioManager)
- Auto-pause on app background, auto-resume on foreground
- Respects phone calls and other media apps

### Widgets
- **VideoPoolScope** — StatefulWidget owning pool lifecycle with device monitoring
- **VideoPoolProvider** — InheritedWidget exposing pool to widget tree (zero dependencies)
- **VideoFeedView** — TikTok/Reels full-screen PageView with snapping
- **VideoListView** — Instagram-style ListView for mixed content feeds
- **VideoCard** — Full lifecycle rendering (thumbnail → loading → playing → error)
- **VisibilityTracker** — Pixel-level intersection ratio computation
- **VideoThumbnail**, **VideoOverlay**, **VideoErrorWidget** — Composable UI building blocks

### Testing
- 96 unit and widget tests
- Mock infrastructure for PlayerAdapter and DeviceMonitor
