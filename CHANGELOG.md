# Changelog

All notable changes to this project will be documented in this file.

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
