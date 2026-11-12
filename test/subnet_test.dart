import 'package:flutter_test/flutter_test.dart';
import 'package:netlook/core/pool.dart';
import 'package:netlook/core/subnet.dart';

void main() {
  test('parse and format ipv4', () {
    expect(formatIpv4(parseIpv4('192.168.1.20')!), '192.168.1.20');
    expect(parseIpv4('256.1.1.1'), isNull);
    expect(parseIpv4('1.2.3'), isNull);
    expect(parseIpv4('a.b.c.d'), isNull);
  });

  test('compareIps is numeric', () {
    final l = ['10.0.0.10', '10.0.0.9', '10.0.0.100']..sort(compareIps);
    expect(l, ['10.0.0.9', '10.0.0.10', '10.0.0.100']);
  });

  test('/24 has 254 hosts without network and broadcast', () {
    final s = Subnet.parse('192.168.1.57', 24)!;
    final h = s.hosts();
    expect(h.length, 254);
    expect(h.first, '192.168.1.1');
    expect(h.last, '192.168.1.254');
    expect(s.key, '192.168.1.0/24');
    expect(s.isCapped, isFalse);
    expect(s.contains('192.168.1.200'), isTrue);
    expect(s.contains('192.168.2.1'), isFalse);
  });

  test('/22 is scanned whole', () {
    final s = Subnet.parse('10.0.5.9', 22)!;
    expect(s.network, parseIpv4('10.0.4.0'));
    expect(s.hosts().length, 1022);
    expect(s.hosts().first, '10.0.4.1');
    expect(s.hosts().last, '10.0.7.254');
  });

  test('wider than /22 is capped to the block around the phone', () {
    final s = Subnet.parse('10.1.130.7', 16)!;
    expect(s.isCapped, isTrue);
    expect(s.scanPrefix, 22);
    final h = s.hosts();
    expect(h.length, 1022);
    expect(h.first, '10.1.128.1');
    expect(h.last, '10.1.131.254');
    expect(h.contains('10.1.130.7'), isTrue);
    expect(s.key, '10.1.0.0/16');
  });

  test('small subnets', () {
    expect(Subnet.parse('192.168.0.5', 30)!.hosts(), ['192.168.0.5', '192.168.0.6']);
    expect(Subnet.parse('192.168.0.5', 31)!.hosts().length, 2);
    expect(Subnet.parse('192.168.0.5', 7), isNull);
  });

  test('private ranges', () {
    expect(isPrivateIpv4(parseIpv4('192.168.0.1')!), isTrue);
    expect(isPrivateIpv4(parseIpv4('172.20.0.1')!), isTrue);
    expect(isPrivateIpv4(parseIpv4('172.32.0.1')!), isFalse);
    expect(isPrivateIpv4(parseIpv4('8.8.8.8')!), isFalse);
  });

  test('forEachLimited respects the limit', () async {
    var running = 0, peak = 0, done = 0;
    await forEachLimited(List.generate(20, (i) => i), 4, (_) async {
      running++;
      if (running > peak) peak = running;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      running--;
      done++;
    });
    expect(done, 20);
    expect(peak, lessThanOrEqualTo(4));
  });
}
