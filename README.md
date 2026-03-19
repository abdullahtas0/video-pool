# video_pool

Enterprise video orchestration for Flutter. Intelligent controller pooling with instance reuse, visibility-based lifecycle management, thermal throttling, disk caching, and ready-to-use widgets.

## Features

- **Controller pooling** -- A fixed pool of player instances that are reused via `swapSource()` instead of dispose/recreate. Zero allocation during normal scrolling.
- **Visibility-based lifecycle** -- Intersection ratios drive play/pause/preload decisions. The most visible video plays; adjacent slots preload; distant slots release.
- **Thermal & memory awareness** -- Native iOS/Android monitoring automatically throttles concurrency when the device overheats or runs low on memory.
- **Disk pre-fetching** -- A 500 MB LRU cache downloads the first bytes of upcoming videos so playback starts instantly.
- **Audio focus** -- System audio session management (AVAudioSession / AudioManager) with automatic background pause/resume.
- **Ready-to-use widgets** -- `VideoFeedView` (TikTok/Reels), `VideoListView` (Instagram), and `VideoCard` handle all wiring for you.

## Quick Start

Three lines of widget code to get a full-screen vertical video feed:

```dart
VideoPoolScope(
  config: const VideoPoolConfig(maxConcurrent: 3, preloadCount: 1),
  adapterFactory: (_) => MediaKitAdapter(),
  sourceResolver: (index) => videos[index],
  child: VideoFeedView(sources: videos),
)
```

### Full example

```dart
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:video_pool/video_pool.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static const videos = [
    VideoSource(url: 'https://example.com/video1.mp4'),
    VideoSource(url: 'https://example.com/video2.mp4'),
    VideoSource(url: 'https://example.com/video3.mp4'),
  ];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: VideoPoolScope(
          config: const VideoPoolConfig(
            maxConcurrent: 3,
            preloadCount: 1,
          ),
          adapterFactory: (_) => MediaKitAdapter(),
          sourceResolver: (index) =>
              index >= 0 && index < videos.length ? videos[index] : null,
          child: const VideoFeedView(sources: videos),
        ),
      ),
    );
  }
}
```

## Architecture

```
VideoPoolScope (widget)
  |-- VideoPool (core engine)
  |     |-- PoolEntry[] (fixed-size array of player slots)
  |     |     `-- PlayerAdapter (media_kit wrapper)
  |     |-- LifecycleOrchestrator
  |     |     `-- LifecyclePolicy (pluggable strategy)
  |     `-- MemoryManager (budget tracking, LRU eviction)
  |-- AudioFocusManager (system audio session)
  `-- DeviceMonitor (thermal + memory native streams)
```

**How scrolling works:**

1. `VideoFeedView` / `VideoListView` compute intersection ratios via `VisibilityTracker`.
2. Ratios are sent to `VideoPool.onVisibilityChanged()`.
3. The `LifecycleOrchestrator` produces a `ReconciliationPlan` (play, pause, preload, release).
4. The pool executes the plan by calling `swapSource()` on idle entries -- never disposing during normal scroll.

## API Reference

### VideoPoolScope

Widget that owns the lifecycle of a `VideoPool`. Place it above your feed widget.

| Parameter | Type | Description |
|---|---|---|
| `config` | `VideoPoolConfig` | Pool sizing and behavior |
| `adapterFactory` | `PlayerAdapter Function(int)` | Creates player instances |
| `sourceResolver` | `VideoSource? Function(int)` | Maps index to video source |
| `child` | `Widget` | The feed widget |

### VideoPoolConfig

| Parameter | Default | Description |
|---|---|---|
| `maxConcurrent` | `3` | Max simultaneous player instances |
| `preloadCount` | `1` | Adjacent slots to preload |
| `memoryBudgetBytes` | `150 MB` | Soft memory budget for all players |
| `visibilityPlayThreshold` | `0.6` | Min visibility to auto-play |
| `visibilityPauseThreshold` | `0.4` | Visibility below which to auto-pause |
| `preloadTimeout` | `10s` | Max time for a preload operation |
| `lifecyclePolicy` | `DefaultLifecyclePolicy` | Custom reconciliation strategy |
| `logLevel` | `LogLevel.none` | Diagnostic logging verbosity |

### VideoFeedView

TikTok/Reels style full-screen `PageView`. Snaps to each video.

### VideoListView

Instagram-style scrollable list. Use with `VideoCard` for video items and any widget for non-video items.

### VideoCard

Individual video widget that listens to pool lifecycle state and renders the appropriate UI (thumbnail, loading, playing, paused, error).

### VideoSource

Immutable value object describing a video resource:

```dart
const VideoSource(
  url: 'https://example.com/video.mp4',
  type: VideoSourceType.network,  // or .file, .asset
  headers: {'Authorization': 'Bearer token'},
  thumbnailUrl: 'https://example.com/thumb.jpg',
)
```

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
    // Only play the primary, release everything else
    return ReconciliationPlan(
      toPlay: {primaryIndex},
      toRelease: currentlyActive.difference({primaryIndex}),
    );
  }
}
```

## Dependencies

| Package | Purpose |
|---|---|
| [media_kit](https://pub.dev/packages/media_kit) | Cross-platform video player |
| [media_kit_video](https://pub.dev/packages/media_kit_video) | Video rendering widget |
| [media_kit_libs_video](https://pub.dev/packages/media_kit_libs_video) | Native video libraries |

## Platform Setup

Follow the [media_kit setup guide](https://github.com/media-kit/media-kit#platform-specific-preparation) for iOS and Android native library configuration.

## License

MIT -- see [LICENSE](LICENSE) for details.
