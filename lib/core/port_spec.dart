/// Port lists for the port scanner. Pure Dart, no I/O.
library;

import 'device_guess.dart';

enum PortPreset {
  common('Common'),
  wellKnown('1–1024'),
  all('All'),
  custom('Custom');

  const PortPreset(this.label);
  final String label;
}

/// Well-known service ports plus the discovery probes, sorted.
List<int> get commonPorts => ({...portNames.keys, ...probePorts}.toList()..sort());

List<int> presetPorts(PortPreset p) => switch (p) {
      PortPreset.common => commonPorts,
      PortPreset.wellKnown => [for (var i = 1; i <= 1024; i++) i],
      PortPreset.all => [for (var i = 1; i <= 65535; i++) i],
      PortPreset.custom => const [],
    };

/// Parses a list like `22, 80-90, 443` into sorted unique ports.
/// Null when any part is invalid or out of 1–65535, or nothing is given.
List<int>? parsePortSpec(String spec) {
  final out = <int>{};
  for (final raw in spec.split(RegExp(r'[,\s]+'))) {
    final part = raw.trim();
    if (part.isEmpty) continue;
    final m = RegExp(r'^(\d{1,5})(?:-(\d{1,5}))?$').firstMatch(part);
    if (m == null) return null;
    final a = int.parse(m.group(1)!);
    final b = m.group(2) == null ? a : int.parse(m.group(2)!);
    if (a < 1 || b > 65535 || a > b) return null;
    for (var p = a; p <= b; p++) {
      out.add(p);
    }
  }
  if (out.isEmpty) return null;
  return out.toList()..sort();
}

/// Ports worth a tap: plain HTTP(S) admin pages the phone can open.
bool isWebPort(int p) => const {80, 81, 443, 3000, 5000, 5001, 8000, 8008, 8080, 8081, 8123, 8443, 8888, 9000, 9090, 9443, 10000, 32400}.contains(p);

/// The browser URL for a web port.
String webUrl(String ip, int port) {
  final tls = const {443, 5001, 8443, 9443, 10000}.contains(port);
  final scheme = tls ? 'https' : 'http';
  final std = (tls && port == 443) || (!tls && port == 80);
  return std ? '$scheme://$ip/' : '$scheme://$ip:$port/';
}
