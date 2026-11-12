import 'package:flutter_test/flutter_test.dart';
import 'package:netlook/core/device.dart';
import 'package:netlook/core/device_guess.dart';
import 'package:netlook/core/ping_stats.dart';

void main() {
  DeviceType g(Set<int> ports, {Set<String> services = const {}, List<String> names = const [], bool gw = false, bool self = false}) =>
      guessType(ports: ports, services: services, names: names, isGateway: gw, isSelf: self);

  test('gateway and self win', () {
    expect(g({80, 443}, gw: true), DeviceType.router);
    expect(g({}, self: true), DeviceType.phone);
  });

  test('ports map to types', () {
    expect(g({9100}), DeviceType.printer);
    expect(g({554, 80}), DeviceType.camera);
    expect(g({62078}), DeviceType.apple);
    expect(g({8009}), DeviceType.tv);
    expect(g({7000}), DeviceType.tv);
    expect(g({445}), DeviceType.computer);
    expect(g({22}), DeviceType.computer);
    expect(g({80}), DeviceType.unknown);
    expect(g({}), DeviceType.unknown);
  });

  test('services map to types', () {
    expect(g({}, services: {'_ipp._tcp'}), DeviceType.printer);
    expect(g({}, services: {'_googlecast._tcp'}), DeviceType.tv);
    expect(g({}, services: {'_hap._tcp'}), DeviceType.smartHome);
    expect(g({}, services: {'_raop._tcp'}), DeviceType.speaker);
    expect(g({}, services: {'_hap._tcp', '_airplay._tcp'}), DeviceType.tv);
    expect(g({}, services: {'_smb._tcp'}), DeviceType.computer);
  });

  test('names help', () {
    expect(g({}, names: ['HP LaserJet 400']), DeviceType.printer);
    expect(g({}, names: ['Ashvini-iPhone']), DeviceType.apple);
  });

  test('serviceLabel', () {
    expect(serviceLabel('_googlecast._tcp.'), 'Google Cast');
    expect(serviceLabel('_foo._tcp'), '_foo._tcp');
    expect(portLabel(62078), '62078 iPhone sync');
    expect(portLabel(1234), '1234');
  });

  test('probe ports are the ones requested', () {
    expect(probePorts, [80, 443, 22, 53, 445, 139, 554, 5353, 8008, 8009, 62078, 7000, 9100]);
  });

  test('device json round trip and merge', () {
    final t = DateTime(2026, 1, 1);
    final stored = <String, Device>{
      '10.0.0.5': Device(ip: '10.0.0.5', firstSeen: t, lastSeen: t, label: 'Dad TV', known: true),
      '10.0.0.6': Device(ip: '10.0.0.6', firstSeen: t, lastSeen: t),
    };
    final now = DateTime(2026, 2, 1);
    final added = mergeScan(stored, [
      Device(ip: '10.0.0.5', firstSeen: now, lastSeen: now, ports: {8009}, names: {'bravia'}),
      Device(ip: '10.0.0.9', firstSeen: now, lastSeen: now, ports: {9100}),
    ]);
    expect(added.map((d) => d.ip), ['10.0.0.9']);
    expect(added.single.type, DeviceType.printer);
    final tv = stored['10.0.0.5']!;
    expect(tv.label, 'Dad TV');
    expect(tv.known, isTrue);
    expect(tv.online, isTrue);
    expect(tv.firstSeen, t);
    expect(tv.lastSeen, now);
    expect(tv.type, DeviceType.tv);
    expect(stored['10.0.0.6']!.online, isFalse);

    final back = Device.fromJson(tv.toJson());
    expect(back.label, 'Dad TV');
    expect(back.ports, {8009});
    expect(back.names, {'bravia'});
    expect(back.displayName, 'Dad TV');
    expect(Device(ip: '1.1.1.1', firstSeen: t, lastSeen: t).displayName, '1.1.1.1');
  });

  test('PingStats', () {
    final s = PingStats([10, null, 20, 30, null]);
    expect(s.sent, 5);
    expect(s.received, 3);
    expect(s.lost, 2);
    expect(s.lossPercent, 40);
    expect(s.min, 10);
    expect(s.max, 30);
    expect(s.avg, 20);
    final none = PingStats([null, null]);
    expect(none.avg, isNull);
  });
}
