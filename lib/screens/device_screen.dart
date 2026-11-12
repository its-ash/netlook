import 'dart:io';

import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../core/device.dart';
import '../core/device_guess.dart';
import '../core/ping_stats.dart';
import '../platform/net_channel.dart';
import '../store/device_store.dart';
import '../widgets/device_icon.dart';

class DeviceScreen extends StatefulWidget {
  const DeviceScreen({
    super.key,
    required this.store,
    required this.platform,
    required this.networkKey,
    required this.ip,
  });

  final DeviceStore store;
  final NetPlatform platform;
  final String networkKey;
  final String ip;

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  static const _pings = 5;
  PingStats? _stats;
  bool _pinging = false;

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
                    icon: deviceIcon(d.type),
                    trailing: UiStatusPill(d.online ? 'Online' : 'Offline', status: d.online ? UiStatus.success : UiStatus.neutral, dot: d.online),
                  ),
                  UiListTile(
                    'Name',
                    icon: Icons.edit_rounded,
                    value: d.label ?? 'Not set',
                    chevron: true,
                    onTap: () => _rename(d),
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
