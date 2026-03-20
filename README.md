# video_pool

Enterprise video orchestration for Flutter. Build TikTok, Reels, and Instagram-style video feeds with intelligent controller pooling, zero-jank scrolling, and automatic device protection.


https://github.com/user-attachments/assets/e19ecf3e-cc93-4eb4-8859-0a7787448cfe


## The Problem

Flutter developers building video feed apps face severe performance issues:

- **Freezing & jank** — creating/destroying `VideoPlayerController` on every scroll causes GC pressure and decoder teardown
- **Overheating** — uncontrolled concurrent video decoders push GPU/CPU to thermal limits
- **Memory leaks & OOM crashes** — each video texture consumes ~15-20MB GPU memory with no orchestration
- **Audio bleeding** — videos continue playing in background or when navigating away

The root cause: **no orchestration layer** manages the lifecycle of video controllers across a scrollable feed.

## The Solution

`video_pool` creates a fixed pool of player instances and **reuses them** as the user scrolls — swapping video sources without destroying the decoder pipeline. Combined with visibility tracking, thermal monitoring, and disk caching, it delivers smooth 60fps feeds on any device.

```dart
// That's it. A full TikTok-style feed in 4 lines of widget code.
VideoPoolScope(
  config: const VideoPoolConfig(maxConcurrent: 3, preloadCount: 1),
  adapterFactory: (_) => MediaKitAdapter(),
  sourceResolver: (index) => videos[index],
  child: VideoFeedView(sources: videos),
)
```

## Features

| Feature | What it does |
|---------|-------------|
| **Controller Pooling** | Fixed pool of N players reused via `swapSource()`. Zero allocation during scroll. |
| **Visibility Lifecycle** | Intersection ratio tracking drives play/pause/preload. Most visible plays, adjacent preloads, distant releases. |
| **Thermal Throttling** | Native iOS/Android monitoring auto-reduces concurrency when device overheats. |
| **Memory Pressure** | Responds to `onTrimMemory(RUNNING_CRITICAL)` with emergency flush to 1 player. |
| **Disk Pre-fetching** | 500MB LRU cache downloads first 2MB of upcoming videos in isolate. Instant playback on scroll-back. |
| **Audio Focus** | System audio session management. Auto-pause on background, phone call, Spotify, other media app. Responds to iOS interruptions and Android focus changes. |
| **Ready-to-use Widgets** | `VideoFeedView` (TikTok), `VideoListView` (Instagram), `VideoCard` — all wiring handled. |
| **Custom Policies** | Pluggable `LifecyclePolicy` for battery-saver, data-saver, or custom behaviors. |
| **Debug Logging** | Configurable `LogLevel` shows pool state, swaps, thermal events in dev console. |

## Quick Start

### 1. Add dependency

```yaml
dependencies:
  video_pool: ^0.3.0
  media_kit: ^1.1.11
  media_kit_video: ^1.2.5
  media_kit_libs_video: ^1.0.5
```

### 2. Initialize

```dart
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:video_pool/video_pool.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MyApp());
}
```

### 3. Build your feed

**TikTok / Reels (full-screen vertical feed):**

```dart
final videos = [
  const VideoSource(url: 'https://example.com/video1.mp4'),
  const VideoSource(url: 'https://example.com/video2.mp4'),
  const VideoSource(url: 'https://example.com/video3.mp4'),
];

@override
Widget build(BuildContext context) {
  return VideoPoolScope(
    config: const VideoPoolConfig(
      maxConcurrent: 3,
      preloadCount: 1,
    ),
    adapterFactory: (_) => MediaKitAdapter(),
    sourceResolver: (index) =>
        index >= 0 && index < videos.length ? videos[index] : null,
    child: VideoFeedView(sources: videos),
  );
}
```

**Instagram (mixed content list):**

```dart
@override
Widget build(BuildContext context) {
  return VideoPoolScope(
    config: const VideoPoolConfig(
      maxConcurrent: 2,
      preloadCount: 1,
      visibilityPlayThreshold: 0.6,
      visibilityPauseThreshold: 0.4,
    ),
    adapterFactory: (_) => MediaKitAdapter(),
    sourceResolver: (index) => getVideoSource(index),
    child: VideoListView(
      itemCount: feedItems.length,
      itemExtent: 400,
      itemBuilder: (context, index) {
        final item = feedItems[index];
        if (item.isVideo) {
          return VideoCard(index: item.videoIndex, source: item.videoSource);
        }
        return TextPostWidget(item);
      },
    ),
  );
}
```

## How It Works

```
User swipes to video 5
         │
    VisibilityTracker computes intersection ratios
         │
    VideoPool.onVisibilityChanged(primary: 5, ratios: {4: 0.1, 5: 0.95, 6: 0.05})
         │
    LifecycleOrchestrator.reconcile()
    ├── Query DeviceMonitor → thermal=nominal, effectiveMax=3
    ├── toRelease: {2}     → Player holding video 2 returns to idle
    ├── toPreload: {6}     → Released player gets swapSource(video6)
    ├── toPlay:   {5}      → Plays (instant if preloaded from previous swipe)
    └── toPause:  {4}      → Pause but keep decoder allocated
         │
    Key: NO player.dispose() happened. Players REUSED via swapSource().
```

### Instance Reuse (Core Innovation)

Traditional approach: `dispose()` + `new Player()` on every scroll → decoder teardown, GC pressure, jank.

video_pool approach: Pool creates N players at init. They are **never disposed** during normal scroll:

```
Pool Init:   Create 3 Player instances
Scroll 1→2:  Player-0 stays on video 1 (pause), Player-1 plays video 2
Scroll 2→3:  Player-0 gets swapSource(video 4) for preload, Player-2 plays video 3
Scroll 3→4:  Player-1 gets swapSource(video 5) for preload, Player-0 plays video 4
...
Result: 3 players handle infinite scroll. Zero GC pressure. Instant transitions.
```

## Architecture

```
VideoPoolScope (widget — owns lifecycle)
├── VideoPool (coordinator — the brain)
│   ├── PoolEntry[0..N] (fixed slots, never disposed during scroll)
│   │   └── PlayerAdapter → MediaKitAdapter (swapSource reuse)
│   ├── LifecycleOrchestrator
│   │   └── LifecyclePolicy (pluggable strategy)
│   ├── MemoryManager (LRU budget tracking, emergency flush)
│   └── FilePreloadManager (isolate-based disk cache)
├── AudioFocusManager (system audio session, lifecycle observer)
├── DeviceMonitor (native thermal + memory streams)
└── VisibilityTracker (intersection ratio computation)
```

## API Reference

### VideoPoolConfig

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `maxConcurrent` | `int` | `3` | Max simultaneous player instances in pool |
| `preloadCount` | `int` | `1` | Number of adjacent slots to preload ahead |
| `memoryBudgetBytes` | `int` | `150 MB` | Soft memory budget for all players combined |
| `visibilityPlayThreshold` | `double` | `0.6` | Min intersection ratio to auto-play (60%) |
| `visibilityPauseThreshold` | `double` | `0.4` | Ratio below which to auto-pause (40%) |
| `preloadTimeout` | `Duration` | `10s` | Max time for a preload operation |
| `lifecyclePolicy` | `LifecyclePolicy?` | `DefaultLifecyclePolicy` | Custom reconciliation strategy |
| `logLevel` | `LogLevel` | `none` | Diagnostic logging: none/error/warning/info/debug |

### VideoSource

```dart
const VideoSource(
  url: 'https://example.com/video.mp4',
  type: VideoSourceType.network,  // .network (default), .file, .asset
  headers: {'Authorization': 'Bearer token'},
  thumbnailUrl: 'https://example.com/thumb.jpg',
  cacheKey: 'custom-key',  // defaults to url
  resolutionHint: ResolutionHint.hd1080,  // for memory estimation
)
```

### Widgets

| Widget | Purpose |
|--------|---------|
| `VideoPoolScope` | Owns pool lifecycle. Place above your feed widget. |
| `VideoFeedView` | TikTok/Reels full-screen `PageView` with snapping. |
| `VideoListView` | Instagram-style scrollable `ListView` for mixed content. |
| `VideoCard` | Individual video with lifecycle rendering (thumbnail → loading → playing → error). |
| `VideoThumbnail` | Placeholder image before video loads. |
| `VideoOverlay` | Play/pause/buffering overlay controls. |
| `VideoErrorWidget` | Error UI with retry button. |

### Custom LifecyclePolicy

Implement `LifecyclePolicy` to control how the pool allocates players:

```dart
class BatterySaverPolicy implements LifecyclePolicy {
  const BatterySaverPolicy();

  @override
  ReconciliationPlan reconcile({
    required int primaryIndex,
    required Map<int, double> visibilityRatios,
    required int effectiveMaxConcurrent,
    required int effectivePreloadCount,
    required Set<int> currentlyActive,
  }) {
    // Only play the primary video, release everything else immediately
    return ReconciliationPlan(
      toPlay: {primaryIndex},
      toRelease: currentlyActive.difference({primaryIndex}),
    );
  }
}

// Usage:
VideoPoolConfig(
  lifecyclePolicy: const BatterySaverPolicy(),
)
```

## Thermal & Memory Behavior

The pool dynamically adapts to device conditions:

| Condition | Effect |
|-----------|--------|
| Thermal nominal/fair | Full `maxConcurrent`, full `preloadCount` |
| Thermal serious | Pool shrinks to `ceil(maxConcurrent * 0.66)`, preloading disabled |
| Thermal critical | Pool shrinks to 1 player only |
| Memory warning | Budget reduced to 70% |
| Memory critical | Budget reduced to 40% |
| Memory terminal (`TRIM_MEMORY_RUNNING_CRITICAL`) | **Emergency flush** — all non-playing players instantly disposed |
| Memory recovery (terminal → normal) | Pool auto-recovers to `maxConcurrent` entries and re-reconciles |

## Platform Setup

This package uses [media_kit](https://pub.dev/packages/media_kit) for video playback. Follow the [media_kit platform setup guide](https://github.com/media-kit/media-kit#platform-specific-preparation) for:

- **iOS**: Add to `Podfile` and run `pod install`
- **Android**: No additional setup needed (uses bundled native libraries)

### Minimum Requirements

| Platform | Minimum Version |
|----------|----------------|
| iOS | 13.0 |
| Android | API 21 (5.0) |
| Flutter | 3.16.0 |
| Dart | 3.2.0 |

## Dependencies

| Package | Purpose |
|---------|---------|
| [media_kit](https://pub.dev/packages/media_kit) | Cross-platform GPU-accelerated video playback |
| [media_kit_video](https://pub.dev/packages/media_kit_video) | Video rendering widget |
| [media_kit_libs_video](https://pub.dev/packages/media_kit_libs_video) | Native video codec libraries |

| [crypto](https://pub.dev/packages/crypto) | SHA-256 hashing for disk cache filenames |

Disk cache uses `dart:io` + `Isolate`. Audio focus uses platform channels. State management uses `InheritedWidget` + `ValueNotifier` — no Provider/Riverpod required.

## Example App

See the [`example/`](example/) directory for three runnable demos:

- **TikTok Feed** — Full-screen vertical video feed with disk caching
- **Instagram Feed** — Mixed content list with video cards and text posts
- **Custom Policy** — Battery-saver lifecycle policy with debug logging

```bash
cd example
flutter run
```

## License

MIT — see [LICENSE](LICENSE) for details.
