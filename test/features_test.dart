import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:netlook/core/device.dart';
import 'package:netlook/core/device_guess.dart';
import 'package:netlook/core/net_map.dart';
import 'package:netlook/core/port_spec.dart';
import 'package:netlook/core/public_ip.dart';
import 'package:netlook/core/wol.dart';
import 'package:netlook/scan/scanner.dart';

Device dev(String ip, {bool gw = false, bool self = false, DeviceType type = DeviceType.unknown}) {
  final t = DateTime(2026);
  return Device(ip: ip, firstSeen: t, lastSeen: t, isGateway: gw, isSelf: self, type: type);
}

void main() {
  group('user type and group', () {
    test('user type wins over the guess and survives a scan', () {
      final d = dev('10.0.0.5', type: DeviceType.computer)..userType = DeviceType.console;
      expect(d.kind, DeviceType.console);
      d.absorb(dev('10.0.0.5')..ports.add(445));
      expect(d.type, DeviceType.computer);
      expect(d.kind, DeviceType.console);
      expect(d.summary, startsWith('Game console'));
    });

    test('json round trip keeps type, group and mac; old json still loads', () {
      final d = dev('10.0.0.5')
        ..userType = DeviceType.storage
        ..group = 'Office'
        ..mac = 'aa:bb:cc:dd:ee:ff';
      final back = Device.fromJson(d.toJson());
      expect(back.userType, DeviceType.storage);
      expect(back.group, 'Office');
      expect(back.mac, 'aa:bb:cc:dd:ee:ff');

      final old = Device.fromJson({'ip': '10.0.0.6', 'type': 'tv'});
      expect(old.userType, isNull);
      expect(old.kind, DeviceType.tv);
      expect(dev('1.1.1.1').toJson().containsKey('utype'), isFalse);
    });

    test('pickable types exclude "This phone"', () {
      expect(DeviceType.pickable, isNot(contains(DeviceType.phone)));
      expect(DeviceType.tryCode('nope'), isNull);
      expect(DeviceType.tryCode('console'), DeviceType.console);
    });
  });

  group('wake-on-lan', () {
    test('parses common MAC formats', () {
      for (final s in ['AA:BB:CC:DD:EE:01', 'aa-bb-cc-dd-ee-01', 'aabb.ccdd.ee01', 'aabbccddee01', ' aa bb cc dd ee 01 ']) {
        expect(normalizeMac(s), 'aa:bb:cc:dd:ee:01', reason: s);
      }
    });

    test('rejects bad MACs', () {
      for (final s in ['', 'aa:bb:cc:dd:ee', 'gg:bb:cc:dd:ee:ff', '00:00:00:00:00:00', 'ff:ff:ff:ff:ff:ff', 'aabbccddeeff00']) {
        expect(parseMac(s), isNull, reason: s);
      }
    });

    test('magic packet is 6 x FF then the MAC 16 times', () {
      final mac = parseMac('01:02:03:04:05:06')!;
      final p = magicPacket(mac);
      expect(p.length, 102);
      expect(p.sublist(0, 6), everyElement(0xFF));
      for (var i = 0; i < 16; i++) {
        expect(p.sublist(6 + i * 6, 12 + i * 6), mac);
      }
      expect(() => magicPacket(Uint8List(5)), throwsArgumentError);
    });
  });

  group('port spec', () {
    test('parses ports and ranges, sorted and unique', () {
      expect(parsePortSpec('443, 80-82 22,80'), [22, 80, 81, 82, 443]);
      expect(parsePortSpec('1-3'), [1, 2, 3]);
      expect(parsePortSpec('65535'), [65535]);
    });

    test('rejects invalid input', () {
      for (final s in ['', ' , ', '0', '65536', '90-80', 'http', '1-2-3', '-5']) {
        expect(parsePortSpec(s), isNull, reason: s);
      }
    });

    test('presets', () {
      expect(presetPorts(PortPreset.wellKnown).length, 1024);
      expect(presetPorts(PortPreset.all).length, 65535);
      final common = presetPorts(PortPreset.common);
      expect(common, containsAll(probePorts));
      expect(common, orderedEquals([...common]..sort()));
    });

    test('web URLs', () {
      expect(webUrl('10.0.0.1', 80), 'http://10.0.0.1/');
      expect(webUrl('10.0.0.1', 443), 'https://10.0.0.1/');
      expect(webUrl('10.0.0.1', 8080), 'http://10.0.0.1:8080/');
      expect(webUrl('10.0.0.1', 8443), 'https://10.0.0.1:8443/');
      expect(isWebPort(22), isFalse);
    });
  });

  group('public ip', () {
    test('parses ipinfo reply and strips the AS number', () {
      final p = parsePublicIp('{"ip":"49.36.1.2","city":"Jaipur","region":"Rajasthan","country":"IN","org":"AS55836 Reliance Jio Infocomm Limited"}')!;
      expect(p.ip, '49.36.1.2');
      expect(p.isp, 'Reliance Jio Infocomm Limited');
      expect(p.place, 'Jaipur, Rajasthan, IN');
    });

    test('IPv6 and missing fields', () {
      final p = parsePublicIp('{"ip":"2401:4900::1"}')!;
      expect(p.isp, isNull);
      expect(p.place, isNull);
    });

    test('rejects junk', () {
      for (final s in ['', 'not json', '[]', '{"ip":5}', '{"ip":"<html>"}', '{"error":"rate limit"}']) {
        expect(parsePublicIp(s), isNull, reason: s);
      }
    });
  });

  group('network map', () {
    test('router in the middle, phone first, everyone placed once', () {
      final devices = [
        dev('10.0.0.9', type: DeviceType.tv),
        dev('10.0.0.1', gw: true),
        dev('10.0.0.7', self: true),
        for (var i = 20; i < 40; i++) dev('10.0.0.$i'),
      ];
      final spots = layoutMap(devices);
      expect(spots.length, devices.length);
      expect(spots.map((s) => s.ip).toSet().length, devices.length);
      expect(spots.first.ip, '10.0.0.1');
      expect(spots.first.ring, 0);
      expect(spots[1].ip, '10.0.0.7');
      // 22 others: ring 1 holds 8, ring 2 holds 14.
      expect(spots.where((s) => s.ring == 1).length, 8);
      expect(spots.where((s) => s.ring == 2).length, 14);
      for (final s in spots.skip(1)) {
        final r = math.sqrt(s.x * s.x + s.y * s.y);
        expect(r, closeTo(s.ring / 2, 1e-9));
      }
    });

    test('no router leaves the center empty', () {
      final spots = layoutMap([dev('10.0.0.2'), dev('10.0.0.3')]);
      expect(spots.every((s) => s.ring == 1), isTrue);
      expect(layoutMap(const []), isEmpty);
    });
  });

  group('scan speed', () {
    test('known hosts are probed first', () {
      final hosts = ['10.0.0.1', '10.0.0.2', '10.0.0.3', '10.0.0.4'];
      expect(orderHosts(hosts, first: ['10.0.0.3', '10.0.0.9', '10.0.0.3', '10.0.0.1']), ['10.0.0.3', '10.0.0.1', '10.0.0.2', '10.0.0.4']);
      expect(orderHosts(hosts), hosts);
    });

    test('timeout adapts to the gateway round trip', () {
      expect(NetScanner.timeoutFor(null).inMilliseconds, 400);
      expect(NetScanner.timeoutFor(2).inMilliseconds, 250);
      expect(NetScanner.timeoutFor(50).inMilliseconds, 350);
      expect(NetScanner.timeoutFor(500).inMilliseconds, 600);
    });

    test('quick ports are a subset of the probe ports', () {
      expect(probePorts, containsAll(quickPorts));
    });
  });
}
