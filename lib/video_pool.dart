/// Enterprise video orchestration for Flutter.
///
/// Provides intelligent controller pooling with instance reuse,
/// visibility-based lifecycle management, thermal throttling,
/// disk caching, and ready-to-use widgets.
library;

// Models
export 'src/core/models/video_source.dart';
export 'src/core/models/playback_config.dart';
export 'src/core/models/thermal_status.dart';

// Memory
export 'src/core/memory/memory_pressure_level.dart';
export 'src/core/memory/lru_cache.dart';

// Adapter
export 'src/core/adapter/player_adapter.dart';
export 'src/core/adapter/player_state.dart';
export 'src/core/adapter/media_kit_adapter.dart';

// Cache
export 'src/core/cache/file_preload_manager.dart';

// Lifecycle
export 'src/core/lifecycle/lifecycle_state.dart';
export 'src/core/lifecycle/lifecycle_policy.dart';
export 'src/core/lifecycle/lifecycle_orchestrator.dart';

// Memory Manager
export 'src/core/memory/memory_manager.dart';

// Events
export 'src/core/events/pool_event.dart';
export 'src/core/events/metrics_snapshot.dart';

// Pool
export 'src/core/pool/pool_config.dart';
export 'src/core/pool/pool_entry.dart';
export 'src/core/pool/pool_statistics.dart';
export 'src/core/pool/video_pool.dart';
export 'src/core/pool/video_pool_logger.dart';

// Platform
export 'src/platform/device_capabilities.dart';
export 'src/platform/device_status.dart';
export 'src/platform/platform_interface.dart';
export 'src/platform/device_monitor.dart';

// Audio
export 'src/core/audio/audio_focus_manager.dart';

// Widgets
export 'src/widgets/video_pool_provider.dart';
export 'src/widgets/video_pool_scope.dart';
export 'src/widgets/visibility_tracker.dart';
export 'src/widgets/video_thumbnail.dart';
export 'src/widgets/video_overlay.dart';
export 'src/widgets/video_error_widget.dart';
export 'src/widgets/video_card.dart';
export 'src/widgets/video_feed_view.dart';
export 'src/widgets/video_list_view.dart';
