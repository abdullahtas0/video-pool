/// Estimates network bandwidth using Exponential Moving Average (EMA)
/// from prefetch download durations.
class BandwidthEstimator {
  /// Creates a [BandwidthEstimator].
  ///
  /// [alpha] is the EMA smoothing factor (0.0–1.0). Higher values give
  /// more weight to recent samples. Default is 0.3.
  BandwidthEstimator({this.alpha = 0.3});

  /// EMA smoothing factor. Higher = more weight on recent samples.
  final double alpha;

  /// Current bandwidth estimate in bytes/second. Null if no samples yet.
  int? get estimatedBytesPerSec => _estimate;
  int? _estimate;

  int _sampleCount = 0;

  /// Record a bandwidth sample from a completed download.
  ///
  /// [bytesReceived]: bytes downloaded.
  /// [durationMs]: download time in milliseconds.
  /// [concurrentDownloads]: number of parallel downloads at time of
  /// measurement — used to estimate total available bandwidth.
  void addSample(int bytesReceived, int durationMs,
      {int concurrentDownloads = 1}) {
    if (durationMs <= 0 || bytesReceived <= 0) return;

    // This download got 1/N of total bandwidth if N downloads were concurrent.
    final singleStreamRate = (bytesReceived * 1000) ~/ durationMs;
    final estimatedTotalRate = singleStreamRate * concurrentDownloads;

    _sampleCount++;
    if (_sampleCount == 1) {
      // Cold-start override: first sample = direct assignment (no EMA bias).
      _estimate = estimatedTotalRate;
    } else {
      // EMA: newEstimate = alpha * sample + (1 - alpha) * previous
      _estimate =
          (alpha * estimatedTotalRate + (1 - alpha) * _estimate!).round();
    }
  }

  /// Reset all samples and the current estimate.
  void reset() {
    _estimate = null;
    _sampleCount = 0;
  }
}
