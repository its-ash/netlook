import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/device.dart';
import '../platform/net_channel.dart';

/// Devices per network (keyed by subnet, e.g. `192.168.1.0/24`) and the
/// new-device alert settings. Persisted in shared preferences.
class DeviceStore extends ChangeNotifier {
  DeviceStore._(this._prefs, this._networks, this._ssids);

  static const _kNetworks = 'netlook.networks';
  static const _kWatch = 'netlook.watch';
  static const _kInterval = 'netlook.interval';
  static const _kWatchKey = 'netlook.watchKey';
  static const _kWatchName = 'netlook.watchName';
  static const _kAutoPublicIp = 'netlook.autoPublicIp';
  static const _kLastScan = 'netlook.lastScanMs';

  static const intervals = [30, 60, 120];

  final SharedPreferences _prefs;
  final Map<String, Map<String, Device>> _networks;
  final Map<String, String> _ssids;

  static Future<DeviceStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    final networks = <String, Map<String, Device>>{};
    final ssids = <String, String>{};
    final raw = prefs.getString(_kNetworks);
    if (raw != null) {
      try {
        final j = jsonDecode(raw) as Map<String, Object?>;
        for (final e in j.entries) {
          final n = e.value as Map<String, Object?>;
          final ssid = n['ssid'] as String?;
          if (ssid != null) ssids[e.key] = ssid;
          networks[e.key] = {
            for (final d in (n['devices'] as List).cast<Map<String, Object?>>()) (d['ip'] as String): Device.fromJson(d),
          };
        }
      } catch (_) {
        // Corrupt data: start fresh.
      }
    }
    return DeviceStore._(prefs, networks, ssids);
  }

  Map<String, Device> _of(String key) => _networks.putIfAbsent(key, () => {});

  List<Device> devices(String networkKey) => _networks[networkKey]?.values.toList() ?? const [];

  String? ssidOf(String networkKey) => _ssids[networkKey];

  /// Merges a scan; returns devices never seen on this network before.
  Future<List<Device>> recordScan(NetInfo info, List<Device> hits) async {
    final key = info.key;
    final stored = _of(key);
    final firstScan = stored.isEmpty;
    final added = mergeScan(stored, hits);
    if (info.ssid != null) _ssids[key] = info.ssid!;
    await _save();
    notifyListeners();
    return firstScan ? const [] : added;
  }

  /// Merges a single-device rescan. [hit] null means the device did not answer.
  Future<void> recordOne(String networkKey, String ip, Device? hit) async {
    final stored = _of(networkKey);
    final existing = stored[ip];
    if (hit == null) {
      existing?.online = false;
    } else if (existing == null) {
      mergeScan({}, [hit]);
      stored[ip] = hit;
    } else {
      existing.absorb(hit);
    }
    notifyListeners();
    await _save();
  }

  /// Group names used on this network, sorted.
  List<String> groups(String networkKey) =>
      ({for (final d in devices(networkKey)) ?d.group}.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())));

  /// Look up the public IP each time the app opens (off: only on tap).
  bool get autoPublicIp => _prefs.getBool(_kAutoPublicIp) ?? false;
  Future<void> setAutoPublicIp(bool v) async {
    await _prefs.setBool(_kAutoPublicIp, v);
    notifyListeners();
  }

  /// How long the last full scan took, for the home screen footer.
  Duration? get lastScanTime {
    final ms = _prefs.getInt(_kLastScan);
    return ms == null ? null : Duration(milliseconds: ms);
  }

  Future<void> setLastScanTime(Duration d) => _prefs.setInt(_kLastScan, d.inMilliseconds);

  Future<void> update(String networkKey, Device d) async {
    notifyListeners();
    await _save();
    if (watchKey == networkKey) onKnownChanged?.call();
  }

  Future<void> markAllKnown(String networkKey) async {
    for (final d in _of(networkKey).values) {
      d.known = true;
    }
    notifyListeners();
    await _save();
    if (watchKey == networkKey) onKnownChanged?.call();
  }

  Future<void> forget(String networkKey, String ip) async {
    _of(networkKey).remove(ip);
    notifyListeners();
    await _save();
    if (watchKey == networkKey) onKnownChanged?.call();
  }

  List<String> knownIps(String networkKey) => [
        for (final d in devices(networkKey))
          if (d.known || d.isGateway || d.isSelf) d.ip,
      ];

  /// Called when known flags of the watched network change, to refresh the worker.
  VoidCallback? onKnownChanged;

  bool get watchEnabled => _prefs.getBool(_kWatch) ?? false;
  int get watchInterval => _prefs.getInt(_kInterval) ?? 60;
  String? get watchKey => _prefs.getString(_kWatchKey);
  String? get watchName => _prefs.getString(_kWatchName);

  Future<void> saveWatch({required bool enabled, int? interval, String? key, String? name}) async {
    await _prefs.setBool(_kWatch, enabled);
    if (interval != null) await _prefs.setInt(_kInterval, interval);
    if (key != null) await _prefs.setString(_kWatchKey, key);
    if (name != null) await _prefs.setString(_kWatchName, name);
    notifyListeners();
  }

  /// Pushes the alert settings and the known IPs to the background worker.
  Future<void> syncWatch(NetPlatform platform) async {
    final key = watchKey;
    await platform.setWatch(
      enabled: watchEnabled && key != null,
      intervalMinutes: watchInterval,
      networkKey: key ?? '',
      knownIps: key == null ? const [] : knownIps(key),
    );
  }

  Future<void> _save() => _prefs.setString(
        _kNetworks,
        jsonEncode({
          for (final e in _networks.entries)
            e.key: {
              'ssid': _ssids[e.key],
              'devices': [for (final d in e.value.values) d.toJson()],
            },
        }),
      );
}
