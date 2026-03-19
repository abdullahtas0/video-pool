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

// Lifecycle
export 'src/core/lifecycle/lifecycle_state.dart';
export 'src/core/lifecycle/lifecycle_policy.dart';
