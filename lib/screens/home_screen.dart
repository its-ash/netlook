import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:theme/theme.dart';

import '../core/device.dart';
import '../core/subnet.dart';
import '../platform/net_channel.dart';
import '../scan/scanner.dart';
import '../store/device_store.dart';
import '../widgets/device_icon.dart';
import 'device_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store, required this.platform});

  final DeviceStore store;
  final NetPlatform platform;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final NetScanner _scanner = NetScanner(widget.platform);
  NetInfo? _info;
  bool _loaded = false;
  bool _scanning = false;
  bool _capped = false;
  ScanProgress? _progress;
  bool _askLocation = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanner.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_scanning) _refreshInfo();
  }

  Future<void> _init() async {
    await _refreshInfo();
    if (_info != null) _scan();
  }

  Future<void> _refreshInfo() async {
    final info = await widget.platform.networkInfo();
    final located = await Permission.locationWhenInUse.isGranted;
    if (!mounted) return;
    setState(() {
      _info = info;
      _loaded = true;
      _askLocation = !located;
    });
  }

  Future<void> _grantLocation() async {
    await Permission.locationWhenInUse.request();
    await _refreshInfo();
  }

  Future<void> _scan() async {
    final info = _info;
    if (info == null || _scanning) return;
    setState(() {
      _scanning = true;
      _progress = const ScanProgress(0, 'Starting scan');
    });
    final result = await _scanner.scan(info, onProgress: (p) {
      if (mounted) setState(() => _progress = p);
    });
    if (result != null) {
      await widget.store.recordScan(info, result.devices);
    }
    if (!mounted) return;
    setState(() {
      _scanning = false;
      _capped = result?.capped ?? false;
    });
  }

  void _open(Device d) {
    final info = _info;
    if (info == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => DeviceScreen(store: widget.store, platform: widget.platform, networkKey: info.key, ip: d.ip),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return UiScaffold(
      appBar: UiAppBar(
        title: 'Netlook',
        back: false,
        actions: [
          UiIconButton(
            Icons.settings_rounded,
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => SettingsScreen(store: widget.store, platform: widget.platform, info: _info),
            )),
          ),
        ],
      ),
      scrollable: true,
      body: ListenableBuilder(listenable: widget.store, builder: (context, _) => _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    final info = _info;
    if (!_loaded) {
      return const Padding(padding: EdgeInsets.only(top: 80), child: Center(child: UiSpinner(size: 28)));
    }
    if (info == null) {
      return UiEmptyState(
        icon: Icons.wifi_off_rounded,
        title: 'Not connected',
        message: 'Connect to a Wi-Fi network to see who is on it.',
        action: UiButton('Try again', icon: Icons.refresh_rounded, onPressed: _init),
      );
    }
    final devices = widget.store.devices(info.key)..sort((a, b) => compareDevices(a, b));
    final online = devices.where((d) => d.online).length;
    final fresh = devices.where((d) => d.online && !d.known && !d.isSelf && !d.isGateway).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(info: info, ssid: info.ssid ?? widget.store.ssidOf(info.key)),
        if (_askLocation && info.ssid == null) ...[
          const UiGap(UiSpace.md),
          UiAlert(
            'Android only gives the Wi-Fi name to apps with location access. '
            'Netlook uses it only to show the name, never to find your position.',
            title: 'Show the Wi-Fi name?',
            action: UiButton('Allow location', size: UiSize.sm, variant: UiButtonVariant.secondary, onPressed: _grantLocation),
          ),
        ],
        const UiGap(UiSpace.lg),
        if (_scanning) ...[
          UiProgressBar(_progress?.fraction, label: _progress?.message ?? 'Scanning'),
          const UiGap(UiSpace.lg),
        ] else
          UiButton('Scan again', icon: Icons.radar_rounded, onPressed: _scan),
        if (_capped) ...[
          const UiGap(UiSpace.md),
          const UiAlert('This network is larger than /22, so only the 1022 addresses around your phone are scanned.', status: UiStatus.warning),
        ],
        const UiGap(UiSpace.lg),
        if (devices.isEmpty && !_scanning)
          const UiEmptyState(icon: Icons.devices_other_rounded, title: 'No devices yet', message: 'Run a scan to list the devices on this network.', compact: true)
        else
          UiListGroup(
            header: '$online online${fresh > 0 ? ' · $fresh not marked known' : ''}',
            footer: 'Android hides other devices\' MAC addresses from apps, so devices are told apart by IP, '
                'name and services only. A device whose IP changes can show up as new.',
            children: [for (final d in devices) _tile(d)],
          ),
      ],
    );
  }

  Widget _tile(Device d) {
    final isNew = !d.known && !d.isSelf && !d.isGateway;
    return UiListTile(
      d.displayName,
      subtitle: d.online ? '${d.ip} · ${d.summary}' : '${d.ip} · last seen ${_ago(d.lastSeen)}',
      icon: deviceIcon(d.type),
      iconStatus: d.online ? (isNew ? UiStatus.warning : UiStatus.accent) : UiStatus.neutral,
      trailing: d.online
          ? (isNew ? const UiStatusPill('New', status: UiStatus.warning) : const UiStatusPill('Online', status: UiStatus.success, dot: true))
          : const UiStatusPill('Offline'),
      chevron: true,
      onTap: () => _open(d),
    );
  }
}

/// Online first, then by IP.
int compareDevices(Device a, Device b) {
  if (a.online != b.online) return a.online ? -1 : 1;
  if (a.isSelf != b.isSelf) return a.isSelf ? -1 : 1;
  if (a.isGateway != b.isGateway) return a.isGateway ? -1 : 1;
  return compareIps(a.ip, b.ip);
}

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

class _Header extends StatelessWidget {
  const _Header({required this.info, required this.ssid});

  final NetInfo info;
  final String? ssid;

  @override
  Widget build(BuildContext context) {
    return UiCard(
      child: Column(
        children: [
          UiKeyValue('Wi-Fi', ssid ?? (info.isWifi ? 'Name hidden' : 'Not Wi-Fi')),
          UiKeyValue('Your IP', info.ip, copyable: true, mono: true),
          UiKeyValue('Gateway', info.gateway ?? 'Unknown', copyable: info.gateway != null, mono: true),
          UiKeyValue('DNS', info.dns.isEmpty ? 'Unknown' : info.dns.join(', '), mono: true),
          UiKeyValue('Network', info.key, mono: true),
        ],
      ),
    );
  }
}
