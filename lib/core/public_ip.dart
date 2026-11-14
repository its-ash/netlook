/// Public IP and internet provider, parsed from the ipinfo.io JSON reply.
/// Pure Dart, no I/O.
library;

import 'dart:convert';

class PublicIpInfo {
  const PublicIpInfo({required this.ip, this.isp, this.city, this.region, this.country});

  final String ip;

  /// Provider name without the AS number, e.g. "Bharti Airtel Ltd.".
  final String? isp;
  final String? city;
  final String? region;
  final String? country;

  String? get place {
    final parts = [city, region, country].whereType<String>().where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(', ');
  }
}

/// The lookup service. Called only when the user asks (or turned on
/// automatic lookups in Settings).
const publicIpUrl = 'https://ipinfo.io/json';

/// Parses `{"ip": "...", "org": "AS9829 National Internet Backbone", ...}`.
/// Null when there is no valid IP in it.
PublicIpInfo? parsePublicIp(String body) {
  Object? j;
  try {
    j = jsonDecode(body);
  } catch (_) {
    return null;
  }
  if (j is! Map) return null;
  final map = j;
  final ip = map['ip'];
  if (ip is! String || !_looksLikeIp(ip)) return null;
  String? str(String k) {
    final v = map[k];
    return v is String && v.trim().isNotEmpty ? v.trim() : null;
  }

  final org = str('org');
  return PublicIpInfo(
    ip: ip,
    isp: org?.replaceFirst(RegExp(r'^AS\d+\s+'), ''),
    city: str('city'),
    region: str('region'),
    country: str('country'),
  );
}

bool _looksLikeIp(String s) =>
    RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(s) || (s.contains(':') && RegExp(r'^[0-9a-fA-F:]+$').hasMatch(s));
