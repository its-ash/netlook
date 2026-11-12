import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/device.dart';
import '../core/device_guess.dart';
import '../core/netbios.dart';
import '../core/pool.dart';
import '../core/ssdp.dart';
import '../core/subnet.dart';
import '../platform/net_channel.dart';

class ScanProgress {
  const ScanProgress(this.fraction, this.message);
  final double fraction;
  final String message;
}

class ScanResult {
  const ScanResult({required this.info, required this.devices, required this.capped});
  final NetInfo info;
  final List<Device> devices;

  /// The network was wider than /22, so only the block around this phone was scanned.
  final bool capped;
}

enum _Tcp { open, refused, closed }

/// Scans the current subnet and identifies what answers. Probes run in Dart
/// (sockets) and in Kotlin (isReachable, NSD).
class NetScanner {
  NetScanner(this.platform);

  final NetPlatform platform;

  static const _hostConcurrency = 32; // x14 sockets each: stays under the fd limit
  static const _tcpTimeout = Duration(milliseconds: 350);

  bool _cancel = false;
  void cancel() => _cancel = true;

  Future<ScanResult?> scan(NetInfo info, {void Function(ScanProgress)? onProgress}) async {
    _cancel = false;
    final subnet = info.subnet;
    if (subnet == null) return null;
    final hosts = subnet.hosts();
    void report(double f, String m) => onProgress?.call(ScanProgress(f.clamp(0, 1), m));

    await platform.setMulticast(true);
    try {
      report(0, 'Starting scan');
      // Discovery that runs alongside the sweep.
      final nsd = platform.browseServices(serviceTypes.keys.toList(), durationMs: 6000);
      final ssdp = _ssdp(subnet);

      // 1. Sweep: ping + TCP probes.
      final alive = <String, Set<int>>{};
      var done = 0;
      await forEachLimited(hosts, _hostConcurrency, (ip) async {
        final r = await _probeHost(ip);
        if (r != null) alive[ip] = r;
        done++;
        if (done % 8 == 0 || done == hosts.length) {
          report(0.8 * done / hosts.length, 'Probing $done of ${hosts.length} addresses');
        }
      }, cancelled: () => _cancel);
      if (_cancel) return null;

      // 2. Names: reverse DNS and NetBIOS for hosts that answered.
      report(0.82, 'Reading names');
      final now = DateTime.now();
      final byIp = <String, Device>{};
      Device dev(String ip) => byIp.putIfAbsent(
            ip,
            () => Device(
              ip: ip,
              firstSeen: now,
              lastSeen: now,
              isGateway: ip == info.gateway,
              isSelf: ip == info.ip,
            ),
          );
      for (final e in alive.entries) {
        dev(e.key).ports.addAll(e.value);
      }
      dev(info.ip); // this phone is always listed
      if (info.gateway != null && subnet.contains(info.gateway!) && alive.containsKey(info.gateway)) {
        dev(info.gateway!);
      }

      final targets = alive.keys.toList();
      await Future.wait([
        forEachLimited(targets, 16, (ip) async {
          final n = await _reverse(ip);
          if (n != null) dev(ip).names.add(n);
        }, cancelled: () => _cancel),
        _netbios(targets).then((m) {
          for (final e in m.entries) {
            final host = e.value.hostName;
            if (host != null) dev(e.key).names.add(host);
          }
        }),
      ]);
      if (_cancel) return null;

      // 3. mDNS and SSDP results.
      report(0.92, 'Waiting for service discovery');
      for (final hit in await nsd) {
        if (!subnet.contains(hit.ip)) continue;
        final d = dev(hit.ip);
        if (hit.name.isNotEmpty) d.names.add(hit.name);
        d.services.add(hit.type);
      }
      final ssdpHits = await ssdp;
      for (final e in ssdpHits.entries) {
        final d = dev(e.key);
        d.names.addAll(e.value.names);
        d.services.addAll(e.value.services);
        d.server = e.value.server ?? d.server;
      }

      final list = byIp.values.toList()
        ..sort((a, b) => compareIps(a.ip, b.ip));
      for (final d in list) {
        d.type = guessType(
          ports: d.ports,
          services: d.services,
          names: d.names,
          ssdpServer: d.server,
          isGateway: d.isGateway,
          isSelf: d.isSelf,
        );
      }
      report(1, 'Done');
      return ScanResult(info: info, devices: list, capped: subnet.isCapped);
    } finally {
      await platform.setMulticast(false);
    }
  }

  /// Open ports when the host is alive, null when nothing answered.
  Future<Set<int>?> _probeHost(String ip) async {
    final results = await Future.wait([
      platform.ping(ip, timeoutMs: 350),
      for (final p in probePorts) _tcp(ip, p),
    ]);
    final pingMs = results.first as double?;
    final open = <int>{};
    var alive = pingMs != null;
    for (var i = 0; i < probePorts.length; i++) {
      final r = results[i + 1] as _Tcp;
      if (r == _Tcp.open) open.add(probePorts[i]);
      if (r != _Tcp.closed) alive = true;
    }
    return alive ? open : null;
  }

  /// A refused connection still proves the host is there (errno 111 Linux, 61 macOS).
  Future<_Tcp> _tcp(String ip, int port) async {
    try {
      final s = await Socket.connect(ip, port, timeout: _tcpTimeout);
      s.destroy();
      return _Tcp.open;
    } on SocketException catch (e) {
      final c = e.osError?.errorCode;
      return (c == 111 || c == 61) ? _Tcp.refused : _Tcp.closed;
    } catch (_) {
      return _Tcp.closed;
    }
  }

  Future<String?> _reverse(String ip) async {
    try {
      final r = await InternetAddress(ip).reverse().timeout(const Duration(milliseconds: 1500));
      final h = r.host;
      if (h == ip || h.isEmpty) return null;
      return h.replaceAll(RegExp(r'\.(local|lan|home|localdomain)\.?$'), '');
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, NetbiosResult>> _netbios(List<String> targets) async {
    final out = <String, NetbiosResult>{};
    RawDatagramSocket? sock;
    try {
      sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      sock.listen((ev) {
        if (ev != RawSocketEvent.read) return;
        final dg = sock!.receive();
        if (dg == null) return;
        final r = parseNbstatResponse(Uint8List.fromList(dg.data));
        if (r != null) out[dg.address.address] = r;
      });
      final q = buildNbstatQuery();
      for (final ip in targets) {
        sock.send(q, InternetAddress(ip), netbiosPort);
      }
      await Future<void>.delayed(const Duration(milliseconds: 1800));
    } catch (_) {
      // UDP blocked: names fall back to the other sources.
    } finally {
      sock?.close();
    }
    return out;
  }

  Future<Map<String, _SsdpInfo>> _ssdp(Subnet subnet) async {
    final responses = <String, SsdpResponse>{};
    RawDatagramSocket? sock;
    try {
      sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      sock.listen((ev) {
        if (ev != RawSocketEvent.read) return;
        final dg = sock!.receive();
        if (dg == null) return;
        final r = parseSsdpResponse(utf8.decode(dg.data, allowMalformed: true));
        if (r == null) return;
        final ip = dg.address.address;
        if (!subnet.contains(ip)) return;
        final prev = responses[ip];
        responses[ip] = SsdpResponse(
          server: prev?.server ?? r.server,
          location: prev?.location ?? r.location,
          st: r.st,
          usn: r.usn,
        );
      });
      final msg = mSearchBytes();
      for (var i = 0; i < 3; i++) {
        sock.send(msg, InternetAddress(ssdpAddress), ssdpPort);
        await Future<void>.delayed(const Duration(milliseconds: 900));
      }
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    } catch (_) {
      // Multicast unavailable.
    } finally {
      sock?.close();
    }

    final out = <String, _SsdpInfo>{};
    await forEachLimited(responses.entries, 8, (e) async {
      final info = _SsdpInfo()..server = e.value.server;
      final st = e.value.st;
      if (st != null && st != 'ssdp:all') info.services.add(st);
      final loc = e.value.location;
      if (loc != null) {
        final desc = await _describe(loc, subnet);
        if (desc != null) {
          if (desc.friendlyName != null) info.names.add(desc.friendlyName!);
          final model = [desc.manufacturer, desc.modelName].whereType<String>().join(' ');
          if (model.isNotEmpty) info.server = info.server == null ? model : '$model, ${info.server}';
          if (desc.deviceType != null) info.services.add(desc.deviceType!);
        }
      }
      out[e.key] = info;
    });
    return out;
  }

  Future<UpnpDescription?> _describe(String location, Subnet subnet) async {
    final uri = Uri.tryParse(location);
    // Only fetch from this network, never from an arbitrary host.
    if (uri == null || uri.scheme != 'http' || !subnet.contains(uri.host)) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 2));
      final res = await req.close().timeout(const Duration(seconds: 2));
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 3));
      final d = parseUpnpDescription(body.length > 200000 ? body.substring(0, 200000) : body);
      return d.isEmpty ? null : d;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}

class _SsdpInfo {
  final names = <String>{};
  final services = <String>{};
  String? server;
}
