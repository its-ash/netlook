import 'package:flutter/services.dart';

import '../core/subnet.dart';

class NetInfo {
  const NetInfo({
    required this.ip,
    required this.prefix,
    this.gateway,
    this.dns = const [],
    this.ssid,
    this.isWifi = true,
  });

  final String ip;
  final int prefix;
  final String? gateway;
  final List<String> dns;

  /// Null unless location permission is granted and Wi-Fi is connected.
  final String? ssid;
  final bool isWifi;

  Subnet? get subnet => Subnet.parse(ip, prefix);
  String get key => subnet?.key ?? '$ip/$prefix';

  static NetInfo? fromMap(Map<Object?, Object?>? m) {
    if (m == null) return null;
    final ip = m['ip'] as String?;
    if (ip == null) return null;
    return NetInfo(
      ip: ip,
      prefix: (m['prefix'] as int?) ?? 24,
      gateway: m['gateway'] as String?,
      dns: ((m['dns'] as List?) ?? const []).cast<String>(),
      ssid: m['ssid'] as String?,
      isWifi: (m['isWifi'] as bool?) ?? true,
    );
  }
}

/// An mDNS / DNS-SD hit resolved by Android's NsdManager.
class NsdHit {
  const NsdHit(this.ip, this.name, this.type);
  final String ip;
  final String name;
  final String type;
}

/// The native side: link properties, multicast lock, ICMP-ish ping, NSD and
/// the background watcher. Abstract so the scanner can be tested.
abstract class NetPlatform {
  Future<NetInfo?> networkInfo();
  Future<void> setMulticast(bool on);

  /// Round-trip time in ms using `InetAddress.isReachable`, or null.
  Future<double?> ping(String ip, {int timeoutMs = 400});
  Future<List<NsdHit>> browseServices(List<String> types, {int durationMs = 5000});

  /// Starts or stops the periodic new-device check.
  Future<void> setWatch({
    required bool enabled,
    required int intervalMinutes,
    required String networkKey,
    required List<String> knownIps,
  });
}

class NetChannel implements NetPlatform {
  const NetChannel();

  static const _ch = MethodChannel('com.itsash.netlook/net');

  @override
  Future<NetInfo?> networkInfo() async {
    try {
      return NetInfo.fromMap(await _ch.invokeMapMethod<Object?, Object?>('networkInfo'));
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<void> setMulticast(bool on) async {
    try {
      await _ch.invokeMethod<void>('multicast', on);
    } on PlatformException {
      // Discovery still works for unicast probes.
    } on MissingPluginException {
      // Not running on Android.
    }
  }

  @override
  Future<double?> ping(String ip, {int timeoutMs = 400}) async {
    try {
      final v = await _ch.invokeMethod<double>('ping', {'ip': ip, 'timeout': timeoutMs});
      return (v == null || v < 0) ? null : v;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<List<NsdHit>> browseServices(List<String> types, {int durationMs = 5000}) async {
    try {
      final r = await _ch.invokeListMethod<Map<Object?, Object?>>('nsd', {'types': types, 'duration': durationMs});
      return [
        for (final m in r ?? const <Map<Object?, Object?>>[])
          if (m['ip'] is String) NsdHit(m['ip'] as String, (m['name'] as String?) ?? '', (m['type'] as String?) ?? ''),
      ];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  @override
  Future<void> setWatch({
    required bool enabled,
    required int intervalMinutes,
    required String networkKey,
    required List<String> knownIps,
  }) async {
    try {
      await _ch.invokeMethod<void>('watch', {
        'enabled': enabled,
        'interval': intervalMinutes,
        'key': networkKey,
        'known': knownIps,
      });
    } on PlatformException {
      // Ignored: the toggle state is still stored.
    } on MissingPluginException {
      // Not running on Android.
    }
  }
}
