import 'dart:io';

import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../core/device.dart';
import '../core/device_guess.dart';
import '../core/ping_stats.dart';
import '../core/wol.dart';
import '../platform/net_channel.dart';
import '../scan/net_tools.dart';
import '../scan/scanner.dart';
import '../store/device_store.dart';
import '../widgets/device_icon.dart';
import 'port_scan_screen.dart';

class DeviceScreen extends StatefulWidget {
  const DeviceScreen({
    super.key,
    required this.store,
    required this.platform,
    required this.info,
    required this.ip,
  });

  final DeviceStore store;
  final NetPlatform platform;
  final NetInfo info;
  final String ip;

  String get networkKey => info.key;

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  static const _pings = 5;
  PingStats? _stats;
  bool _pinging = false;
  bool _rescanning = false;
  bool _waking = false;
  late final NetScanner _scanner = NetScanner(widget.platform);

  @override
  void dispose() {
    _scanner.cancel();
    super.dispose();
  }

  Device? get _device {
    for (final d in widget.store.devices(widget.networkKey)) {
      if (d.ip == widget.ip) return d;
    }
    return null;
  }

  Future<void> _rename(Device d) async {
    final v = await UiDialog.prompt(
      context,
      title: 'Name this device',
      message: 'Only stored on this phone. Leave empty to remove the name.',
      label: 'Name',
      initialValue: d.label ?? '',
    );
    if (v == null) return;
    d.label = v.trim().isEmpty ? null : v.trim();
    await widget.store.update(widget.networkKey, d);
  }

  Future<void> _pickType(Device d) async {
    const auto = 'auto';
    final v = await UiActionSheet.show<String>(
      context,
      title: 'Device type',
      message: 'Your choice replaces the guess and is kept across scans.',
      actions: [
        UiSheetAction(auto, value: auto, icon: Icons.auto_awesome_rounded, subtitle: 'Guess: ${d.type.label}'),
        for (final t in DeviceType.pickable) UiSheetAction(t.label, value: t.code, icon: deviceIcon(t)),
      ],
    );
    if (v == null) return;
    d.userType = v == auto ? null : DeviceType.tryCode(v);
    await widget.store.update(widget.networkKey, d);
  }

  Future<void> _pickGroup(Device d) async {
    const none = '\u0000none', create = '\u0000new';
    final existing = widget.store.groups(widget.networkKey);
    var v = existing.isEmpty
        ? create
        : await UiActionSheet.show<String>(
            context,
            title: 'Group',
            message: 'Group devices by room or by owner.',
            actions: [
              for (final g in existing) UiSheetAction(g, value: g, icon: g == d.group ? Icons.check_rounded : Icons.folder_outlined),
              const UiSheetAction('New group', value: create, icon: Icons.create_new_folder_outlined),
              if (d.group != null) const UiSheetAction('No group', value: none, icon: Icons.folder_off_outlined),
            ],
          );
    if (v == null || !mounted) return;
    if (v == create) {
      v = await UiDialog.prompt(
        context,
        title: 'New group',
        message: 'For example Living room, Kids or Office.',
        label: 'Group name',
        initialValue: existing.isEmpty ? (d.group ?? '') : '',
        validator: (s) => s.trim().isEmpty ? 'Enter a name' : null,
      );
      if (v == null) return;
    }
    d.group = v == none ? null : v.trim();
    await widget.store.update(widget.networkKey, d);
  }

  Future<void> _editMac(Device d) async {
    final v = await UiDialog.prompt(
      context,
      title: 'MAC address',
      message: 'Android does not let apps read it. Find it in your router\'s device list or in the computer\'s network settings. Leave empty to remove it.',
      label: 'MAC address',
      hint: 'aa:bb:cc:dd:ee:ff',
      initialValue: d.mac ?? '',
      validator: (s) => s.trim().isEmpty || normalizeMac(s) != null ? null : 'Use 12 hex digits, like aa:bb:cc:dd:ee:ff',
    );
    if (v == null) return;
    d.mac = v.trim().isEmpty ? null : normalizeMac(v);
    await widget.store.update(widget.networkKey, d);
  }

  Future<void> _wake(Device d) async {
    final mac = parseMac(d.mac ?? '');
    if (mac == null) return;
    setState(() => _waking = true);
    final ok = await sendWakeOnLan(mac, subnet: widget.info.subnet);
    if (!mounted) return;
    setState(() => _waking = false);
    context.showToast(
      ok ? 'Wake signal sent. The device can take up to a minute to come online.' : 'Could not send the wake signal.',
      status: ok ? UiStatus.success : UiStatus.danger,
    );
  }

  Future<void> _rescan(Device d) async {
    setState(() => _rescanning = true);
    final hit = await _scanner.scanOne(widget.info, d.ip);
    if (!mounted) return;
    await widget.store.recordOne(widget.networkKey, d.ip, hit);
    if (!mounted) return;
    setState(() => _rescanning = false);
    context.showToast(hit == null ? 'No reply. The device may be asleep or gone.' : 'Device updated.',
        status: hit == null ? UiStatus.warning : UiStatus.success);
  }

  void _portScan(Device d) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PortScanScreen(ip: d.ip, name: d.displayName)));
  }

  Future<void> _setKnown(Device d, bool v) async {
    d.known = v;
    await widget.store.update(widget.networkKey, d);
  }

  Future<void> _forget(Device d) async {
    final ok = await UiDialog.confirm(
      context,
      title: 'Forget this device?',
      message: 'It is removed from the list and its name is lost. It comes back if it is seen again.',
      confirmLabel: 'Forget',
      destructive: true,
    );
    if (!ok) return;
    await widget.store.forget(widget.networkKey, d.ip);
    if (mounted) Navigator.of(context).pop();
  }

  Future<double?> _tcpTime(String ip, int port) async {
    final sw = Stopwatch()..start();
    try {
      final s = await Socket.connect(ip, port, timeout: const Duration(milliseconds: 800));
      sw.stop();
      s.destroy();
      return sw.elapsedMicroseconds / 1000;
    } on SocketException catch (e) {
      // A refusal is still an answer from the host.
      final c = e.osError?.errorCode;
      if (c == 111 || c == 61) return sw.elapsedMicroseconds / 1000;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _ping(Device d) async {
    setState(() {
      _pinging = true;
      _stats = null;
    });
    final samples = <double?>[];
    for (var i = 0; i < _pings; i++) {
      var ms = await widget.platform.ping(d.ip, timeoutMs: 800);
      if (ms == null && d.ports.isNotEmpty) ms = await _tcpTime(d.ip, d.ports.first);
      samples.add(ms);
      if (!mounted) return;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    if (!mounted) return;
    setState(() {
      _pinging = false;
      _stats = PingStats(samples);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final d = _device;
        if (d == null) {
          return const UiScaffold(appBar: UiAppBar(title: 'Device'), body: UiEmptyState(title: 'Device not found'));
        }
        return UiScaffold(
          appBar: UiAppBar(title: d.displayName, subtitle: d.ip),
          scrollable: true,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UiListGroup(
                children: [
                  UiListTile(
                    d.displayName,
                    subtitle: d.summary,
                    icon: deviceIcon(d.kind),
                    trailing: UiStatusPill(d.online ? 'Online' : 'Offline', status: d.online ? UiStatus.success : UiStatus.neutral, dot: d.online),
                  ),
                  UiListTile(
                    'Name',
                    icon: Icons.edit_rounded,
                    value: d.label ?? 'Not set',
                    chevron: true,
                    onTap: () => _rename(d),
                  ),
                  if (!d.isSelf)
                    UiListTile(
                      'Type',
                      icon: Icons.category_rounded,
                      value: d.userType == null ? '${d.type.label} (guess)' : d.userType!.label,
                      chevron: true,
                      onTap: () => _pickType(d),
                    ),
                  UiListTile(
                    'Group',
                    icon: Icons.folder_rounded,
                    value: d.group ?? 'None',
                    chevron: true,
                    onTap: () => _pickGroup(d),
                  ),
                  UiSwitchTile(
                    'Known device',
                    subtitle: 'Known devices do not trigger new-device alerts',
                    icon: Icons.verified_user_rounded,
                    value: d.known || d.isSelf || d.isGateway,
                    onChanged: (d.isSelf || d.isGateway) ? null : (v) => _setKnown(d, v),
                  ),
                ],
              ),
              const UiGap(UiSpace.lg),
              UiListGroup(
                header: 'Details',
                footer: 'No MAC address or maker: Android 10+ does not let apps read them.',
                children: [
                  UiListTile('IP address', value: d.ip),
                  if (d.names.isNotEmpty) UiListTile('Names', subtitle: d.names.join('\n'), maxSubtitleLines: 6),
                  if (d.services.isNotEmpty) UiListTile('Services', subtitle: _services(d), maxSubtitleLines: 8),
                  UiListTile('Open ports', subtitle: d.ports.isEmpty ? 'None found' : (d.ports.toList()..sort()).map(portLabel).join('\n'), maxSubtitleLines: 12),
                  if (d.server != null) UiListTile('Software', subtitle: d.server, maxSubtitleLines: 4),
                  UiListTile('First seen', value: _stamp(d.firstSeen)),
                  UiListTile('Last seen', value: _stamp(d.lastSeen)),
                ],
              ),
              const UiGap(UiSpace.lg),
              if (!d.isSelf) ...[
                UiListGroup(
                  header: 'Wake-on-LAN',
                  footer: 'Turns on a sleeping computer or NAS that has Wake-on-LAN enabled. It must be wired or support wake over Wi-Fi.',
                  children: [
                    UiListTile('MAC address', icon: Icons.memory_rounded, value: d.mac ?? 'Not set', chevron: true, onTap: () => _editMac(d)),
                  ],
                ),
                const UiGap(UiSpace.md),
                UiButton(
                  'Wake device',
                  icon: Icons.power_settings_new_rounded,
                  variant: UiButtonVariant.secondary,
                  loading: _waking,
                  onPressed: d.mac == null || _waking ? null : () => _wake(d),
                ),
                const UiGap(UiSpace.lg),
              ],
              UiListGroup(
                header: 'Tools',
                children: [
                  UiListTile(
                    'Rescan this device',
                    subtitle: 'Ports, names and services, without a full network scan',
                    icon: Icons.refresh_rounded,
                    trailing: _rescanning ? const UiSpinner(size: 18) : null,
                    chevron: !_rescanning,
                    onTap: _rescanning ? null : () => _rescan(d),
                  ),
                  UiListTile(
                    'Scan ports',
                    subtitle: 'Common ports, 1–1024, all, or your own list',
                    icon: Icons.lan_rounded,
                    chevron: true,
                    onTap: () => _portScan(d),
                  ),
                ],
              ),
              const UiGap(UiSpace.lg),
              UiButton(_pinging ? 'Pinging' : 'Ping test', icon: Icons.network_ping_rounded, loading: _pinging, onPressed: _pinging || d.isSelf ? null : () => _ping(d)),
              if (_stats != null) ...[const UiGap(UiSpace.md), _result(_stats!)],
              const UiGap(UiSpace.xl),
              if (!d.isSelf)
                UiButton('Forget device', variant: UiButtonVariant.danger, icon: Icons.delete_outline_rounded, onPressed: () => _forget(d)),
            ],
          ),
        );
      },
    );
  }

  String _services(Device d) =>
      d.services.map((s) => s.startsWith('_') ? serviceLabel(s) : s.split(':').reversed.skip(1).take(1).join()).where((e) => e.isNotEmpty).toSet().join('\n');

  Widget _result(PingStats s) {
    if (s.received == 0) {
      return const UiAlert('No reply. The device may be asleep, or it blocks pings and has no open port to test.', status: UiStatus.warning);
    }
    String ms(double? v) => '${v!.toStringAsFixed(1)} ms';
    return UiCard(
      child: Column(
        children: [
          UiKeyValue('Average', ms(s.avg)),
          UiKeyValue('Fastest', ms(s.min)),
          UiKeyValue('Slowest', ms(s.max)),
          UiKeyValue('Lost', '${s.lost} of ${s.sent}'),
        ],
      ),
    );
  }

  String _stamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}
