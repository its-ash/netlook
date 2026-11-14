import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../core/device_guess.dart';
import '../core/port_spec.dart';
import '../scan/port_scanner.dart';

class PortScanScreen extends StatefulWidget {
  const PortScanScreen({super.key, required this.ip, required this.name});

  final String ip;
  final String name;

  @override
  State<PortScanScreen> createState() => _PortScanScreenState();
}

class _PortScanScreenState extends State<PortScanScreen> {
  final _scanner = PortScanner();
  final _custom = TextEditingController(text: '20-25, 80, 443, 8000-8100');
  PortPreset _preset = PortPreset.common;
  String? _customError;

  bool _running = false;
  int _total = 0;
  int _done = 0;
  final _open = <int>[];
  Duration? _took;
  bool _stopped = false;

  @override
  void dispose() {
    _scanner.cancel();
    _custom.dispose();
    super.dispose();
  }

  List<int>? _ports() {
    if (_preset != PortPreset.custom) return presetPorts(_preset);
    final p = parsePortSpec(_custom.text);
    setState(() => _customError = p == null ? 'Use numbers 1–65535 and ranges, like 22, 80-90, 443' : null);
    return p;
  }

  Future<void> _start() async {
    final ports = _ports();
    if (ports == null) return;
    FocusScope.of(context).unfocus();
    final watch = Stopwatch()..start();
    setState(() {
      _running = true;
      _stopped = false;
      _total = ports.length;
      _done = 0;
      _open.clear();
      _took = null;
    });
    await _scanner.scan(
      widget.ip,
      ports,
      onOpen: (p) {
        if (mounted) setState(() => _open..add(p)..sort());
      },
      onProgress: (d) {
        if (mounted) setState(() => _done = d);
      },
    );
    if (!mounted) return;
    setState(() {
      _running = false;
      _stopped = _scanner.cancelled;
      _took = watch.elapsed;
    });
  }

  void _stop() => _scanner.cancel();

  @override
  Widget build(BuildContext context) {
    return UiScaffold(
      appBar: UiAppBar(title: 'Port scan', subtitle: '${widget.name} · ${widget.ip}'),
      scrollable: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UiChoiceChips<PortPreset>(
            options: [for (final p in PortPreset.values) UiChoice(p, p.label)],
            value: _preset,
            onChanged: _running ? null : (p) => setState(() => _preset = p),
          ),
          const UiGap(UiSpace.md),
          if (_preset == PortPreset.custom) ...[
            UiTextField(
              controller: _custom,
              label: 'Ports',
              hint: '22, 80-90, 443',
              helper: 'Single ports and ranges, separated by commas',
              error: _customError,
              keyboardType: TextInputType.text,
              enabled: !_running,
            ),
            const UiGap(UiSpace.md),
          ],
          if (_preset == PortPreset.all && !_running)
            ...[
              const UiAlert('Scanning all 65,535 ports takes a few minutes. Keep the screen on.', status: UiStatus.info),
              const UiGap(UiSpace.md),
            ],
          if (_running) ...[
            UiProgressBar(_total == 0 ? null : _done / _total, label: 'Checked $_done of $_total ports · ${_open.length} open'),
            const UiGap(UiSpace.md),
            UiButton('Stop', icon: Icons.stop_rounded, variant: UiButtonVariant.secondary, onPressed: _stop),
          ] else
            UiButton('Start scan', icon: Icons.play_arrow_rounded, onPressed: _start),
          if (!_running && _took == null && _preset != PortPreset.custom) ...[
            const UiGap(UiSpace.sm),
            Text('${presetPorts(_preset).length} ports, up to ${_etaFor(presetPorts(_preset).length)}',
                style: context.text.bodySmall, textAlign: TextAlign.center),
          ],
          const UiGap(UiSpace.lg),
          if (_took != null && _open.isEmpty)
            UiEmptyState(
              icon: Icons.lock_outline_rounded,
              title: 'No open ports',
              message: '${_stopped ? 'Stopped after $_done' : 'Checked $_done'} ports in ${_fmt(_took!)}. '
                  'The device may block connections, or nothing is listening.',
              compact: true,
            )
          else if (_open.isNotEmpty)
            UiListGroup(
              header: '${_open.length} open${_took != null ? ' · ${_stopped ? 'stopped, ' : ''}$_done ports in ${_fmt(_took!)}' : ''}',
              footer: 'Open means the device accepted a connection. Tap a web port to open it in the browser.',
              children: [for (final p in _open) _tile(p)],
            ),
        ],
      ),
    );
  }

  /// Worst case: every port filtered, so each slot waits the 0.5 s timeout.
  String _etaFor(int n) {
    final secs = (n / PortScanner.concurrency * 0.5).ceil();
    return secs < 60 ? '$secs s' : '${(secs / 60).ceil()} min';
  }

  Widget _tile(int p) {
    final web = isWebPort(p);
    return UiListTile(
      '$p',
      subtitle: portNames[p] ?? 'Unknown service',
      icon: web ? Icons.language_rounded : Icons.lan_outlined,
      iconStatus: _risky.contains(p) ? UiStatus.warning : UiStatus.accent,
      chevron: web,
      onTap: web ? () => UiUrl.open(webUrl(widget.ip, p)) : null,
    );
  }

  /// Services that are often insecure on a home network.
  static const _risky = {21, 23, 135, 445, 1433, 3306, 3389, 5555, 5900, 6379, 7547};

  String _fmt(Duration d) => d.inSeconds < 60 ? '${(d.inMilliseconds / 1000).toStringAsFixed(1)} s' : '${d.inMinutes} min ${d.inSeconds % 60} s';
}
