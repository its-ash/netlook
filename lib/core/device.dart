/// A device seen on the network, identified by IP (no MAC on Android 10+).
library;

import 'device_guess.dart';

class Device {
  Device({
    required this.ip,
    Set<String>? names,
    Set<String>? services,
    Set<int>? ports,
    required this.firstSeen,
    required this.lastSeen,
    this.label,
    this.known = false,
    this.type = DeviceType.unknown,
    this.isGateway = false,
    this.isSelf = false,
    this.online = false,
    this.server,
  })  : names = names ?? <String>{},
        services = services ?? <String>{},
        ports = ports ?? <int>{};

  final String ip;

  /// Names discovered from reverse DNS, NetBIOS, mDNS and UPnP.
  final Set<String> names;

  /// DNS-SD service types ("_airplay._tcp") and UPnP device types seen.
  final Set<String> services;
  final Set<int> ports;
  final DateTime firstSeen;
  DateTime lastSeen;

  /// The user's own name for the device.
  String? label;
  bool known;
  DeviceType type;
  bool isGateway;
  bool isSelf;

  /// Seen in the latest scan (not stored).
  bool online;

  /// SSDP SERVER header, when the device answered.
  String? server;

  String get displayName {
    if (label != null && label!.trim().isNotEmpty) return label!.trim();
    if (isSelf) return 'This phone';
    if (names.isNotEmpty) return names.first;
    if (isGateway) return 'Router';
    return ip;
  }

  /// Short line under the name: type plus the first services.
  String get summary {
    final parts = <String>[type.label];
    final svc = services.where((s) => s.startsWith('_')).map(serviceLabel).toSet().take(2);
    parts.addAll(svc);
    return parts.join(' · ');
  }

  /// Fills discovery fields from a scan hit, keeping user fields.
  void absorb(Device found) {
    names.addAll(found.names);
    services.addAll(found.services);
    ports
      ..clear()
      ..addAll(found.ports);
    isGateway = found.isGateway;
    isSelf = found.isSelf;
    server = found.server ?? server;
    lastSeen = found.lastSeen;
    online = true;
    type = guessType(
      ports: ports,
      services: services,
      names: names,
      ssdpServer: server,
      isGateway: isGateway,
      isSelf: isSelf,
    );
  }

  Map<String, Object?> toJson() => {
        'ip': ip,
        'names': names.toList(),
        'services': services.toList(),
        'ports': ports.toList(),
        'first': firstSeen.millisecondsSinceEpoch,
        'last': lastSeen.millisecondsSinceEpoch,
        'label': label,
        'known': known,
        'type': type.code,
        'gw': isGateway,
        'self': isSelf,
        'server': server,
      };

  static Device fromJson(Map<String, Object?> j) => Device(
        ip: j['ip'] as String,
        names: {...((j['names'] as List?) ?? const []).cast<String>()},
        services: {...((j['services'] as List?) ?? const []).cast<String>()},
        ports: {...((j['ports'] as List?) ?? const []).cast<int>()},
        firstSeen: DateTime.fromMillisecondsSinceEpoch((j['first'] as int?) ?? 0),
        lastSeen: DateTime.fromMillisecondsSinceEpoch((j['last'] as int?) ?? 0),
        label: j['label'] as String?,
        known: (j['known'] as bool?) ?? false,
        type: DeviceType.fromCode(j['type'] as String?),
        isGateway: (j['gw'] as bool?) ?? false,
        isSelf: (j['self'] as bool?) ?? false,
        server: j['server'] as String?,
      );
}

/// Merges a scan into the stored devices of one network. Returns the devices
/// that were never seen before. Stored devices not in [hits] are marked offline.
List<Device> mergeScan(Map<String, Device> stored, Iterable<Device> hits) {
  final added = <Device>[];
  for (final d in stored.values) {
    d.online = false;
  }
  for (final hit in hits) {
    final existing = stored[hit.ip];
    if (existing == null) {
      hit.online = true;
      hit.type = guessType(
        ports: hit.ports,
        services: hit.services,
        names: hit.names,
        ssdpServer: hit.server,
        isGateway: hit.isGateway,
        isSelf: hit.isSelf,
      );
      stored[hit.ip] = hit;
      added.add(hit);
    } else {
      existing.absorb(hit);
    }
  }
  return added;
}
