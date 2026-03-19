/// Categorizes system memory pressure into actionable levels.
///
/// The video pool uses this to decide how aggressively to reclaim
/// player instances and evict cached data.
enum MemoryPressureLevel {
  /// Plenty of memory available. Operate normally.
  normal,

  /// Memory is getting tight. Stop preloading, evict disk cache.
  warning,

  /// Memory is critically low. Release idle players immediately.
  critical,

  /// Imminent OOM. Emergency disposal of ALL non-primary players.
  terminal,
}
