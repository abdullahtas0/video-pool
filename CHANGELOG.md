# Changelog

All notable changes to this project will be documented in this file.

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
