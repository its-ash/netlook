/// Wake-on-LAN: MAC parsing and the magic packet. Pure Dart, no I/O.
library;

import 'dart:typed_data';

/// UDP ports Wake-on-LAN listeners use (9 discard, 7 echo).
const wolPorts = <int>[9, 7];

/// Parses `aa:bb:cc:dd:ee:ff`, `aa-bb-…`, `aabb.ccdd.eeff` or `aabbccddeeff`
/// (any case). Null when invalid, all zero or broadcast.
Uint8List? parseMac(String s) {
  final hex = s.trim().replaceAll(RegExp(r'[:\-.\s]'), '');
  if (!RegExp(r'^[0-9a-fA-F]{12}$').hasMatch(hex)) return null;
  final out = Uint8List(6);
  for (var i = 0; i < 6; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  if (out.every((b) => b == 0) || out.every((b) => b == 0xFF)) return null;
  return out;
}

/// `aa:bb:cc:dd:ee:ff`, lower case.
String formatMac(Uint8List mac) => [for (final b in mac) b.toRadixString(16).padLeft(2, '0')].join(':');

/// Normalizes user input to `aa:bb:cc:dd:ee:ff`, or null when invalid.
String? normalizeMac(String s) {
  final m = parseMac(s);
  return m == null ? null : formatMac(m);
}

/// 6 × 0xFF followed by the MAC 16 times (102 bytes).
Uint8List magicPacket(Uint8List mac) {
  if (mac.length != 6) throw ArgumentError('MAC must be 6 bytes');
  final p = Uint8List(102);
  p.fillRange(0, 6, 0xFF);
  for (var i = 0; i < 16; i++) {
    p.setRange(6 + i * 6, 12 + i * 6, mac);
  }
  return p;
}
