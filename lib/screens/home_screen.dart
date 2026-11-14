import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:theme/theme.dart';

import '../core/device.dart';
import '../core/public_ip.dart';
import '../core/subnet.dart';
import '../platform/net_channel.dart';
import '../scan/net_tools.dart';
import '../scan/scanner.dart';
import '../store/device_store.dart';
import '../widgets/device_icon.dart';
import 'device_screen.dart';
import 'map_screen.dart';
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
  PublicIpInfo? _public;
  bool _publicLoading = false;
  String? _publicError;

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
    if (_info != null) {
      if (widget.store.autoPublicIp) _lookupPublicIp();
      _scan();
    }
  }

  Future<void> _lookupPublicIp() async {
    if (_publicLoading) return;
    setState(() {
      _publicLoading = true;
      _publicError = null;
    });
    PublicIpInfo? info;
    String? error;
    try {
      info = await fetchPublicIp();
    } catch (_) {
      error = 'Lookup failed';
    }
    if (!mounted) return;
    setState(() {
      _publicLoading = false;
      _public = info ?? _public;
      _publicError = error;
    });
  }

  Future<void> _refreshInfo() async {
    final info = await widget.platform.networkInfo();
    final located = await Permission.locationWhenInUse.isGranted;
    if (!mounted) return;
    setState(() {
      // Another network (or none) means another public IP.
      if (info?.key != _info?.key) _public = null;
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
    final result = await _scanner.scan(
      info,
      hints: [for (final d in widget.store.devices(info.key)) d.ip],
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );
    if (result != null) {
      await widget.store.recordScan(info, result.devices);
      await widget.store.setLastScanTime(result.elapsed);
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
      builder: (_) => DeviceScreen(store: widget.store, platform: widget.platform, info: info, ip: d.ip),
    ));
  }

  void _openMap() {
    final info = _info;
    if (info == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => MapScreen(store: widget.store, platform: widget.platform, info: info),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return UiScaffold(
      appBar: UiAppBar(
        title: 'Netlook',
        back: false,
        actions: [
          if (_info != null)
            UiIconButton(Icons.hub_rounded, tooltip: 'Network map', onPressed: _openMap),
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
        _Header(
          info: info,
          ssid: info.ssid ?? widget.store.ssidOf(info.key),
          public: _public,
          publicLoading: _publicLoading,
          publicError: _publicError,
          onPublic: _lookupPublicIp,
        ),
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
          ..._groups(devices, online, fresh),
      ],
    );
  }

  /// One list, or one list per group when the user has grouped devices.
  List<Widget> _groups(List<Device> devices, int online, int fresh) {
    final took = widget.store.lastScanTime;
    final footer = '${took != null ? 'Last scan took ${(took.inMilliseconds / 1000).toStringAsFixed(1)} s. ' : ''}'
        'Android hides other devices\' MAC addresses from apps, so devices are told apart by IP, '
        'name and services only. A device whose IP changes can show up as new.';
    final summary = '$online online${fresh > 0 ? ' · $fresh not marked known' : ''}';
    final names = widget.store.groups(_info!.key);
    if (names.isEmpty) {
      return [UiListGroup(header: summary, footer: footer, children: [for (final d in devices) _tile(d)])];
    }
    final ungrouped = [for (final d in devices) if (d.group == null) d];
    final sections = <Widget>[];
    for (final g in names) {
      final members = [for (final d in devices) if (d.group == g) d];
      final on = members.where((d) => d.online).length;
      sections
        ..add(UiListGroup(header: '$g · $on of ${members.length} online', children: [for (final d in members) _tile(d)]))
        ..add(const UiGap(UiSpace.lg));
    }
    if (ungrouped.isNotEmpty) {
      sections.add(UiListGroup(header: 'Other · $summary', footer: footer, children: [for (final d in ungrouped) _tile(d)]));
    } else {
      sections.removeLast();
    }
    return sections;
  }

  Widget _tile(Device d) {
    final isNew = !d.known && !d.isSelf && !d.isGateway;
    return UiListTile(
      d.displayName,
      subtitle: d.online ? '${d.ip} · ${d.summary}' : '${d.ip} · last seen ${_ago(d.lastSeen)}',
      icon: deviceIcon(d.kind),
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
  const _Header({
    required this.info,
    required this.ssid,
    required this.public,
    required this.publicLoading,
    required this.publicError,
    required this.onPublic,
  });

  final NetInfo info;
  final String? ssid;
  final PublicIpInfo? public;
  final bool publicLoading;
  final String? publicError;
  final VoidCallback onPublic;

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
          if (public != null) ...[
            UiKeyValue('Public IP', public!.ip, copyable: true, mono: true),
            if (public!.isp != null) UiKeyValue('Provider', public!.isp!),
            if (public!.place != null) UiKeyValue('Location (approx.)', public!.place!),
          ] else
            UiKeyValue.custom(
              'Public IP',
              child: publicLoading
                  ? const UiSpinner(size: 16)
                  : UiButton(
                      publicError == null ? 'Look up' : 'Retry',
                      size: UiSize.sm,
                      variant: UiButtonVariant.soft,
                      icon: Icons.public_rounded,
                      onPressed: onPublic,
                    ),
            ),
        ],
      ),
    );
  }
}
