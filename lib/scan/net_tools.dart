import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/public_ip.dart';
import '../core/subnet.dart';
import '../core/wol.dart';

/// Sends the Wake-on-LAN magic packet for [mac] to the subnet's broadcast
/// address and to 255.255.255.255, on ports 9 and 7, three times each.
/// Returns false when the socket could not send.
Future<bool> sendWakeOnLan(Uint8List mac, {Subnet? subnet}) async {
  final packet = magicPacket(mac);
  final targets = <InternetAddress>{
    InternetAddress('255.255.255.255'),
    if (subnet != null) InternetAddress(formatIpv4(subnet.broadcast)),
  };
  RawDatagramSocket? sock;
  try {
    sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    sock.broadcastEnabled = true;
    var sent = 0;
    for (var round = 0; round < 3; round++) {
      for (final t in targets) {
        for (final port in wolPorts) {
          sent += sock.send(packet, t, port) > 0 ? 1 : 0;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return sent > 0;
  } catch (_) {
    return false;
  } finally {
    sock?.close();
  }
}

/// Looks up the public IP and provider. Throws on network errors.
Future<PublicIpInfo> fetchPublicIp() async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5)
    ..userAgent = 'Netlook';
  try {
    final req = await client.getUrl(Uri.parse(publicIpUrl)).timeout(const Duration(seconds: 6));
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final res = await req.close().timeout(const Duration(seconds: 6));
    final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 6));
    if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
    final info = parsePublicIp(body);
    if (info == null) throw const FormatException('Unexpected reply');
    return info;
  } finally {
    client.close(force: true);
  }
}
