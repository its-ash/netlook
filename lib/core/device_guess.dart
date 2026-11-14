/// Guesses what a device is from open ports, advertised services and names.
/// Heuristics only: there is no MAC address on Android 10+, so no vendor lookup.
library;

enum DeviceType {
  router('Router', 'router'),
  phone('This phone', 'phone'),
  apple('Apple device', 'apple'),
  tv('TV or cast device', 'tv'),
  speaker('Speaker', 'speaker'),
  printer('Printer', 'printer'),
  camera('Camera', 'camera'),
  computer('Computer or server', 'computer'),
  smartHome('Smart home', 'home'),
  mobile('Phone or tablet', 'mobile'),
  console('Game console', 'console'),
  storage('Storage (NAS)', 'nas'),
  unknown('Unknown device', 'unknown');

  const DeviceType(this.label, this.code);
  final String label;
  final String code;

  static DeviceType fromCode(String? c) =>
      DeviceType.values.firstWhere((t) => t.code == c, orElse: () => DeviceType.unknown);

  /// Null when [c] is not a type code (used for the optional user override).
  static DeviceType? tryCode(String? c) {
    for (final t in DeviceType.values) {
      if (t.code == c) return t;
    }
    return null;
  }

  /// Types the user can pick for a device ("This phone" is set automatically).
  static List<DeviceType> get pickable => [for (final t in values) if (t != phone) t];
}

/// TCP ports probed on every host.
const probePorts = <int>[80, 443, 22, 53, 445, 139, 554, 5353, 8008, 8009, 62078, 7000, 9100];

/// Ports probed first to find live hosts quickly. A refused connection on any
/// port also proves the host is there; these are the ones firewalled devices
/// most often leave open.
const quickPorts = <int>[80, 443, 62078, 445, 8009, 22];

const portNames = <int, String>{
  20: 'FTP data',
  21: 'FTP',
  22: 'SSH',
  23: 'Telnet',
  25: 'SMTP',
  53: 'DNS',
  80: 'HTTP',
  81: 'HTTP alt',
  88: 'Kerberos',
  110: 'POP3',
  111: 'RPC',
  135: 'MS RPC',
  139: 'NetBIOS',
  143: 'IMAP',
  389: 'LDAP',
  443: 'HTTPS',
  445: 'SMB',
  465: 'SMTPS',
  515: 'Printer (LPD)',
  548: 'AFP',
  554: 'RTSP',
  587: 'SMTP submit',
  631: 'IPP',
  873: 'rsync',
  993: 'IMAPS',
  995: 'POP3S',
  1080: 'SOCKS',
  1194: 'OpenVPN',
  1400: 'Sonos',
  1433: 'MS SQL',
  1723: 'PPTP',
  1880: 'Node-RED',
  1883: 'MQTT',
  1900: 'UPnP',
  2049: 'NFS',
  3000: 'Web app',
  3306: 'MySQL',
  3389: 'Remote Desktop',
  4070: 'Spotify Connect',
  5000: 'UPnP / NAS',
  5001: 'NAS HTTPS',
  5060: 'SIP',
  5222: 'XMPP',
  5353: 'mDNS',
  5432: 'PostgreSQL',
  5555: 'Android ADB',
  5900: 'VNC',
  6379: 'Redis',
  6668: 'Tuya',
  7000: 'AirPlay',
  7547: 'TR-069',
  8000: 'HTTP alt',
  8008: 'Cast HTTP',
  8009: 'Cast',
  8080: 'HTTP proxy',
  8081: 'HTTP alt',
  8123: 'Home Assistant',
  8443: 'HTTPS alt',
  8554: 'RTSP alt',
  8883: 'MQTT TLS',
  8888: 'HTTP alt',
  9000: 'Web admin',
  9090: 'Web admin',
  9100: 'Print (RAW)',
  9443: 'HTTPS alt',
  10000: 'Webmin',
  32400: 'Plex',
  37777: 'Dahua DVR',
  49152: 'UPnP',
  62078: 'iPhone sync',
};

String portLabel(int p) => portNames.containsKey(p) ? '$p ${portNames[p]}' : '$p';

/// mDNS / DNS-SD service types browsed, with a readable label.
const serviceTypes = <String, String>{
  '_googlecast._tcp': 'Google Cast',
  '_airplay._tcp': 'AirPlay',
  '_ipp._tcp': 'Printer (IPP)',
  '_printer._tcp': 'Printer (LPD)',
  '_http._tcp': 'Web',
  '_hap._tcp': 'HomeKit',
  '_spotify-connect._tcp': 'Spotify Connect',
  '_raop._tcp': 'AirPlay audio',
  '_smb._tcp': 'File sharing (SMB)',
};

String serviceLabel(String type) {
  final t = type.replaceAll(RegExp(r'\.$'), '');
  final key = t.split('.').take(2).join('.');
  return serviceTypes[key] ?? key;
}

/// Everything known about a device, used to guess its type.
DeviceType guessType({
  required Set<int> ports,
  Set<String> services = const {},
  Iterable<String> names = const [],
  String? ssdpServer,
  bool isGateway = false,
  bool isSelf = false,
}) {
  if (isSelf) return DeviceType.phone;
  if (isGateway) return DeviceType.router;
  final svc = services.map((s) => s.split('.').take(2).join('.')).toSet();
  final text = '${names.join(' ')} ${ssdpServer ?? ''}'.toLowerCase();

  bool has(String s) => svc.contains(s);
  bool mentions(List<String> w) => w.any(text.contains);

  if (has('_ipp._tcp') || has('_printer._tcp') || ports.contains(9100) || mentions(['printer', 'laserjet', 'officejet', 'epson', 'canon'])) {
    return DeviceType.printer;
  }
  if (ports.contains(554) || mentions(['camera', 'ipcam', 'hikvision', 'dahua', 'nvr'])) {
    return DeviceType.camera;
  }
  if (has('_hap._tcp') && !has('_airplay._tcp')) return DeviceType.smartHome;
  if (has('_raop._tcp') && !has('_airplay._tcp') && !has('_googlecast._tcp')) return DeviceType.speaker;
  if (mentions(['sonos', 'echo', 'speaker', 'soundbar', 'homepod'])) return DeviceType.speaker;
  if (ports.contains(62078) || mentions(['iphone', 'ipad', 'macbook', 'apple', 'imac', 'airport'])) {
    return DeviceType.apple;
  }
  if (has('_googlecast._tcp') || has('_airplay._tcp') || ports.contains(8008) || ports.contains(8009) || ports.contains(7000) || mentions(['chromecast', 'roku', 'bravia', 'samsung tv', 'lg webos', 'smarttv', 'tv', 'android tv', 'fire tv'])) {
    return DeviceType.tv;
  }
  if (has('_hap._tcp') || mentions(['philips hue', 'tasmota', 'esp', 'shelly', 'tuya'])) return DeviceType.smartHome;
  if (has('_smb._tcp') || ports.contains(445) || ports.contains(139) || ports.contains(22) || mentions(['desktop', 'laptop', 'windows', 'ubuntu', 'linux', 'nas', 'synology', 'pc'])) {
    return DeviceType.computer;
  }
  return DeviceType.unknown;
}
