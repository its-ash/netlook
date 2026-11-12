/// SSDP / UPnP helpers: M-SEARCH request, response parsing, description XML.
library;

import 'dart:convert';

const ssdpAddress = '239.255.255.250';
const ssdpPort = 1900;

String buildMSearch({String st = 'ssdp:all', int mx = 2}) => 'M-SEARCH * HTTP/1.1\r\n'
    'HOST: $ssdpAddress:$ssdpPort\r\n'
    'MAN: "ssdp:discover"\r\n'
    'MX: $mx\r\n'
    'ST: $st\r\n'
    '\r\n';

List<int> mSearchBytes({String st = 'ssdp:all', int mx = 2}) => utf8.encode(buildMSearch(st: st, mx: mx));

class SsdpResponse {
  const SsdpResponse({this.server, this.location, this.st, this.usn});
  final String? server;
  final String? location;
  final String? st;
  final String? usn;

  /// Host part of [location], e.g. `192.168.1.20`.
  String? get locationHost => location == null ? null : Uri.tryParse(location!)?.host;
}

/// Parses an SSDP datagram (HTTP-like headers). Null when it is not a 200 or NOTIFY.
SsdpResponse? parseSsdpResponse(String text) {
  final lines = const LineSplitter().convert(text);
  if (lines.isEmpty) return null;
  final first = lines.first.toUpperCase();
  if (!first.startsWith('HTTP/1.1 200') && !first.startsWith('NOTIFY')) return null;
  final headers = <String, String>{};
  for (final l in lines.skip(1)) {
    final i = l.indexOf(':');
    if (i <= 0) continue;
    headers[l.substring(0, i).trim().toLowerCase()] = l.substring(i + 1).trim();
  }
  return SsdpResponse(server: headers['server'], location: headers['location'], st: headers['st'] ?? headers['nt'], usn: headers['usn']);
}

class UpnpDescription {
  const UpnpDescription({this.friendlyName, this.manufacturer, this.modelName, this.deviceType});
  final String? friendlyName;
  final String? manufacturer;
  final String? modelName;
  final String? deviceType;

  bool get isEmpty => friendlyName == null && manufacturer == null && modelName == null;
}

String? _tag(String xml, String tag) {
  final m = RegExp('<$tag[^>]*>([^<]*)</$tag>', caseSensitive: false).firstMatch(xml);
  final v = m?.group(1)?.trim();
  if (v == null || v.isEmpty) return null;
  return v
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'");
}

/// Reads the first (root) device's names from a UPnP description document.
UpnpDescription parseUpnpDescription(String xml) => UpnpDescription(
      friendlyName: _tag(xml, 'friendlyName'),
      manufacturer: _tag(xml, 'manufacturer'),
      modelName: _tag(xml, 'modelName'),
      deviceType: _tag(xml, 'deviceType'),
    );
