/// Device thermal level reported by the OS.
///
/// Used by the orchestrator to throttle concurrent playback and preloading
/// when the device is overheating. Higher levels result in more aggressive
/// throttling to protect device health and battery life.
enum ThermalLevel {
  /// Normal operating temperature. No throttling applied.
  nominal,

  /// Slightly elevated temperature. Minor throttling may apply.
  fair,

  /// High temperature. Significant throttling — reduce concurrent players.
  serious,

  /// Critical temperature. Emergency throttling — pause all non-primary playback.
  critical,
}
