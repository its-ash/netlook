/// Latency summary for the ping test. [samples] holds milliseconds, null for a lost probe.
library;

class PingStats {
  PingStats(List<double?> samples)
      : sent = samples.length,
        _ok = [for (final s in samples) ?s];

  final int sent;
  final List<double> _ok;

  int get received => _ok.length;
  int get lost => sent - received;
  double get lossPercent => sent == 0 ? 0 : lost * 100 / sent;
  double? get min => _ok.isEmpty ? null : _ok.reduce((a, b) => a < b ? a : b);
  double? get max => _ok.isEmpty ? null : _ok.reduce((a, b) => a > b ? a : b);
  double? get avg => _ok.isEmpty ? null : _ok.reduce((a, b) => a + b) / _ok.length;
}
