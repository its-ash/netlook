/// Layout of the network map: the router in the middle, devices on rings
/// around it, grouped by type so similar devices sit together. Pure Dart.
library;

import 'dart:math' as math;

import 'device.dart';
import 'subnet.dart';

class MapSpot {
  const MapSpot(this.ip, this.x, this.y, this.ring);
  final String ip;

  /// Position in units of the outer ring radius, centered on the router (0, 0).
  final double x, y;

  /// 0 for the center, 1.. for the rings.
  final int ring;
}

/// Devices per ring: the first ring holds 8, each next one 6 more.
int ringCapacity(int ring) => 8 + (ring - 1) * 6;

/// Places [devices] around the router. When there is no router in the list,
/// the center stays empty. The phone always comes first on the first ring.
List<MapSpot> layoutMap(List<Device> devices) {
  final center = devices.where((d) => d.isGateway).firstOrNull;
  final rest = [for (final d in devices) if (d != center) d]..sort((a, b) {
      if (a.isSelf != b.isSelf) return a.isSelf ? -1 : 1;
      final t = a.kind.index.compareTo(b.kind.index);
      return t != 0 ? t : compareIps(a.ip, b.ip);
    });

  final spots = <MapSpot>[if (center != null) MapSpot(center.ip, 0, 0, 0)];
  var rings = 0;
  for (var left = rest.length; left > 0; left -= ringCapacity(++rings)) {}
  var i = 0;
  for (var ring = 1; ring <= rings; ring++) {
    final n = math.min(ringCapacity(ring), rest.length - i);
    final r = ring / rings;
    // Offset even rings by half a step so nodes don't line up radially.
    final start = -math.pi / 2 + (ring.isEven ? math.pi / n : 0);
    for (var k = 0; k < n; k++, i++) {
      final a = start + 2 * math.pi * k / n;
      spots.add(MapSpot(rest[i].ip, r * math.cos(a), r * math.sin(a), ring));
    }
  }
  return spots;
}
