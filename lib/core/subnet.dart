/// IPv4 and subnet math. Pure Dart, no I/O.
library;

/// Parses a dotted IPv4 string to a 32-bit int, or null when invalid.
int? parseIpv4(String s) {
  final parts = s.trim().split('.');
  if (parts.length != 4) return null;
  var v = 0;
  for (final p in parts) {
    if (p.isEmpty || p.length > 3) return null;
    final n = int.tryParse(p);
    if (n == null || n < 0 || n > 255) return null;
    v = (v << 8) | n;
  }
  return v;
}

String formatIpv4(int v) => '${(v >> 24) & 255}.${(v >> 16) & 255}.${(v >> 8) & 255}.${v & 255}';

/// Orders dotted IPv4 strings numerically (invalid strings go last).
int compareIps(String a, String b) {
  final x = parseIpv4(a), y = parseIpv4(b);
  if (x == null && y == null) return a.compareTo(b);
  if (x == null) return 1;
  if (y == null) return -1;
  return x.compareTo(y);
}

bool isPrivateIpv4(int v) {
  final a = (v >> 24) & 255, b = (v >> 16) & 255;
  return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168) || (a == 169 && b == 254);
}

/// An IPv4 network: the phone's address plus a prefix length.
class Subnet {
  const Subnet(this.address, this.prefix);

  /// Largest scan: /22 = 1022 hosts. Smaller prefixes are narrowed around the
  /// phone's address; larger ones (/25 and up) are scanned whole.
  static const minScanPrefix = 22;
  static const maxScanPrefix = 30;

  final int address;
  final int prefix;

  static Subnet? parse(String ip, int prefix) {
    final a = parseIpv4(ip);
    if (a == null || prefix < 8 || prefix > 32) return null;
    return Subnet(a, prefix);
  }

  int get mask => prefix == 0 ? 0 : (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
  int get network => address & mask;
  int get broadcast => network | (~mask & 0xFFFFFFFF);

  /// The prefix actually scanned: never wider than /22.
  int get scanPrefix => prefix < minScanPrefix ? minScanPrefix : prefix;

  /// The part of the network that is scanned (our own block when capped).
  Subnet get scanSubnet => Subnet(address, scanPrefix);

  bool get isCapped => prefix < minScanPrefix;

  /// Key identifying the network, e.g. `192.168.1.0/24`.
  String get key => '${formatIpv4(network)}/$prefix';

  /// Host addresses to probe, as dotted strings (network and broadcast removed).
  List<String> hosts() {
    final s = scanSubnet;
    if (s.prefix >= 31) {
      return [for (var i = s.network; i <= s.broadcast; i++) formatIpv4(i)];
    }
    return [for (var i = s.network + 1; i < s.broadcast; i++) formatIpv4(i)];
  }

  bool contains(String ip) {
    final v = parseIpv4(ip);
    return v != null && (v & mask) == network;
  }

  @override
  String toString() => key;
}
