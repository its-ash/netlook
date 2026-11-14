import 'dart:io';

import '../core/pool.dart';

/// TCP connect scan of one host. Only "open" (a completed connection) counts.
class PortScanner {
  // 200 sockets at once stays far below Android's per-app fd limit.
  static const concurrency = 200;

  bool _cancel = false;
  void cancel() => _cancel = true;
  bool get cancelled => _cancel;

  /// Scans [ports] on [ip]. [onOpen] is called as soon as a port is found,
  /// [onProgress] with the number of ports done. Returns the open ports.
  Future<List<int>> scan(
    String ip,
    List<int> ports, {
    Duration timeout = const Duration(milliseconds: 500),
    void Function(int port)? onOpen,
    void Function(int done)? onProgress,
  }) async {
    _cancel = false;
    final open = <int>[];
    var done = 0;
    await forEachLimited(ports, concurrency, (p) async {
      try {
        final s = await Socket.connect(ip, p, timeout: timeout);
        s.destroy();
        open.add(p);
        onOpen?.call(p);
      } catch (_) {
        // Closed, filtered or refused.
      }
      done++;
      if (done % 50 == 0 || done == ports.length) onProgress?.call(done);
    }, cancelled: () => _cancel);
    return open..sort();
  }
}
