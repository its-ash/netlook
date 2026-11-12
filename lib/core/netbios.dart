/// NetBIOS node status (NBSTAT) over UDP 137.
library;

import 'dart:typed_data';

const netbiosPort = 137;

/// Wildcard "*" name query, type NBSTAT (0x21).
Uint8List buildNbstatQuery([int transactionId = 0x4E4C]) {
  final b = BytesBuilder();
  b.add([transactionId >> 8, transactionId & 0xFF]);
  b.add([0x00, 0x00]); // flags: query
  b.add([0x00, 0x01]); // questions
  b.add([0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);
  b.add([0x20]); // name length 32
  // "*" padded with NULs, first-level encoded: 'CK' then 'AA' x 15.
  b.add('CKAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'.codeUnits);
  b.add([0x00]);
  b.add([0x00, 0x21]); // NBSTAT
  b.add([0x00, 0x01]); // IN
  return b.toBytes();
}

class NetbiosName {
  const NetbiosName(this.name, this.suffix, this.isGroup);
  final String name;
  final int suffix;
  final bool isGroup;
}

class NetbiosResult {
  const NetbiosResult(this.names);
  final List<NetbiosName> names;

  /// The workstation name (suffix 0x00, unique), the best device name.
  String? get hostName {
    for (final n in names) {
      if (n.suffix == 0x00 && !n.isGroup) return n.name;
    }
    return null;
  }

  String? get workgroup {
    for (final n in names) {
      if (n.suffix == 0x00 && n.isGroup) return n.name;
    }
    return null;
  }
}

/// Parses an NBSTAT response; null when malformed or without names.
NetbiosResult? parseNbstatResponse(Uint8List d) {
  // Header 12 + name (34) + type/class (4) + ttl (4) + rdlength (2) = 56, then count.
  if (d.length < 57) return null;
  final flags = (d[2] << 8) | d[3];
  if (flags & 0x8000 == 0) return null; // not a response
  var p = 12;
  // Skip the answer name: either a pointer (2 bytes) or labels.
  if (d[p] & 0xC0 == 0xC0) {
    p += 2;
  } else {
    while (p < d.length && d[p] != 0) {
      p += d[p] + 1;
    }
    p += 1;
  }
  p += 2 + 2 + 4 + 2; // type, class, ttl, rdlength
  if (p >= d.length) return null;
  final count = d[p++];
  final names = <NetbiosName>[];
  for (var i = 0; i < count; i++) {
    if (p + 18 > d.length) break;
    final raw = String.fromCharCodes(d.sublist(p, p + 15)).trim();
    final suffix = d[p + 15];
    final nameFlags = (d[p + 16] << 8) | d[p + 17];
    p += 18;
    if (raw.isEmpty) continue;
    names.add(NetbiosName(raw, suffix, nameFlags & 0x8000 != 0));
  }
  return names.isEmpty ? null : NetbiosResult(names);
}
