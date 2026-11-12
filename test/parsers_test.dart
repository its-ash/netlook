import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:netlook/core/netbios.dart';
import 'package:netlook/core/ssdp.dart';

void main() {
  group('ssdp', () {
    test('M-SEARCH request', () {
      final m = buildMSearch();
      expect(m, startsWith('M-SEARCH * HTTP/1.1\r\n'));
      expect(m, contains('HOST: 239.255.255.250:1900\r\n'));
      expect(m, contains('MAN: "ssdp:discover"\r\n'));
      expect(m, contains('ST: ssdp:all\r\n'));
      expect(m, endsWith('\r\n\r\n'));
    });

    test('parses a response', () {
      const text = 'HTTP/1.1 200 OK\r\n'
          'CACHE-CONTROL: max-age=1800\r\n'
          'LOCATION: http://192.168.1.20:8080/desc.xml\r\n'
          'SERVER: Linux/4.9 UPnP/1.0 Sonos/70.3\r\n'
          'ST: urn:schemas-upnp-org:device:ZonePlayer:1\r\n'
          'USN: uuid:abc::urn:schemas-upnp-org:device:ZonePlayer:1\r\n\r\n';
      final r = parseSsdpResponse(text)!;
      expect(r.server, 'Linux/4.9 UPnP/1.0 Sonos/70.3');
      expect(r.location, 'http://192.168.1.20:8080/desc.xml');
      expect(r.locationHost, '192.168.1.20');
      expect(r.st, contains('ZonePlayer'));
    });

    test('ignores other datagrams', () {
      expect(parseSsdpResponse('M-SEARCH * HTTP/1.1\r\nST: x\r\n\r\n'), isNull);
      expect(parseSsdpResponse(''), isNull);
    });

    test('parses NOTIFY with NT', () {
      final r = parseSsdpResponse('NOTIFY * HTTP/1.1\r\nNT: upnp:rootdevice\r\nLOCATION: http://10.0.0.2/d.xml\r\n\r\n')!;
      expect(r.st, 'upnp:rootdevice');
    });

    test('parses description xml', () {
      const xml = '<?xml version="1.0"?><root xmlns="urn:schemas-upnp-org:device-1-0"><device>'
          '<deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>'
          '<friendlyName>Living Room &amp; TV</friendlyName>'
          '<manufacturer>Sony</manufacturer><modelName>BRAVIA 4K</modelName></device></root>';
      final d = parseUpnpDescription(xml);
      expect(d.friendlyName, 'Living Room & TV');
      expect(d.manufacturer, 'Sony');
      expect(d.modelName, 'BRAVIA 4K');
      expect(d.deviceType, contains('MediaRenderer'));
      expect(parseUpnpDescription('<root/>').isEmpty, isTrue);
    });
  });

  group('netbios', () {
    test('query layout', () {
      final q = buildNbstatQuery();
      expect(q.length, 50);
      expect(q[12], 0x20);
      expect(String.fromCharCodes(q.sublist(13, 45)), 'CK${'A' * 30}');
      expect(q[45], 0);
      expect((q[46] << 8) | q[47], 0x21);
      expect((q[48] << 8) | q[49], 1);
    });

    Uint8List response(List<(String, int, int)> names) {
      final b = BytesBuilder();
      b.add([0x4E, 0x4C, 0x84, 0x00, 0, 0, 0, 1, 0, 0, 0, 0]);
      b.add([0x20]);
      b.add('CKAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'.codeUnits);
      b.add([0, 0x00, 0x21, 0x00, 0x01, 0, 0, 0, 0]);
      final rd = 1 + names.length * 18 + 46;
      b.add([rd >> 8, rd & 255, names.length]);
      for (final n in names) {
        b.add(n.$1.padRight(15).codeUnits);
        b.add([n.$2, n.$3 >> 8, n.$3 & 255]);
      }
      b.add(List.filled(46, 0));
      return b.toBytes();
    }

    test('parses node status names', () {
      final r = parseNbstatResponse(response([('DESKTOP-ABC', 0x00, 0x0400), ('WORKGROUP', 0x00, 0x8400), ('DESKTOP-ABC', 0x20, 0x0400)]))!;
      expect(r.names.length, 3);
      expect(r.hostName, 'DESKTOP-ABC');
      expect(r.workgroup, 'WORKGROUP');
    });

    test('rejects garbage and queries', () {
      expect(parseNbstatResponse(Uint8List(10)), isNull);
      expect(parseNbstatResponse(buildNbstatQuery()), isNull);
      expect(parseNbstatResponse(response([])), isNull);
    });
  });
}
