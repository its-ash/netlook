import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../core/device.dart';
import '../core/net_map.dart';
import '../platform/net_channel.dart';
import '../store/device_store.dart';
import '../widgets/device_icon.dart';
import 'device_screen.dart';

/// The router in the middle and every device around it. Pinch to zoom, drag
/// to pan, tap a device to open it.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.store, required this.platform, required this.info});

  final DeviceStore store;
  final NetPlatform platform;
  final NetInfo info;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const _node = 48.0;
  static const _label = 88.0;
  final _transform = TransformationController();
  bool _showOffline = false;
  double? _fittedFor;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  /// Canvas side length: big enough that nodes on the outer ring don't overlap.
  static double canvasSide(List<MapSpot> spots) {
    final rings = spots.fold<int>(0, (m, s) => math.max(m, s.ring));
    if (rings == 0) return 320;
    final outer = ringCapacity(rings);
    final byCircumference = outer * (_label + 8) / (2 * math.pi);
    final byRings = rings * 110.0;
    return 2 * math.max(byCircumference, byRings) + _label + 40;
  }

  void _open(Device d) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => DeviceScreen(store: widget.store, platform: widget.platform, info: widget.info, ip: d.ip),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return UiScaffold(
      appBar: UiAppBar(
        title: 'Network map',
        subtitle: widget.info.ssid ?? widget.store.ssidOf(widget.info.key) ?? widget.info.key,
        actions: [
          UiIconButton(
            Icons.center_focus_strong_rounded,
            tooltip: 'Fit to screen',
            onPressed: () => setState(() => _fittedFor = null),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          final all = widget.store.devices(widget.info.key);
          final offline = all.where((d) => !d.online).length;
          final devices = [for (final d in all) if (d.online || _showOffline || d.isGateway) d];
          if (devices.isEmpty) {
            return const UiEmptyState(icon: Icons.hub_rounded, title: 'Nothing to show', message: 'Run a scan first.');
          }
          final spots = layoutMap(devices);
          final byIp = {for (final d in devices) d.ip: d};
          final side = canvasSide(spots);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: LayoutBuilder(builder: (context, box) {
                  _fit(box.biggest, side);
                  return ClipRect(
                    child: InteractiveViewer(
                      transformationController: _transform,
                      constrained: false,
                      minScale: 0.2,
                      maxScale: 3,
                      boundaryMargin: EdgeInsets.all(side / 2),
                      child: SizedBox.square(
                        dimension: side,
                        child: Stack(
                          children: [
                            Positioned.fill(child: CustomPaint(painter: _Links(spots, byIp, context.colors))),
                            for (final s in spots) _nodeAt(s, byIp[s.ip]!, side),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const UiGap(UiSpace.sm),
              _legend(context),
              if (offline > 0) ...[
                const UiGap(UiSpace.sm),
                UiSwitchTile(
                  'Show offline devices',
                  subtitle: '$offline not seen in the last scan',
                  value: _showOffline,
                  onChanged: (v) => setState(() {
                    _showOffline = v;
                    _fittedFor = null;
                  }),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// Scales the canvas to fit the view once per layout (and after "Fit").
  void _fit(Size view, double side) {
    if (_fittedFor == side || view.isEmpty) return;
    _fittedFor = side;
    final scale = math.min(1.0, math.min(view.width, view.height) / side);
    final dx = (view.width - side * scale) / 2;
    final dy = (view.height - side * scale) / 2;
    // Not during layout: InteractiveViewer rebuilds when the transform changes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _transform.value = Matrix4.identity()
        ..translateByDouble(dx, dy, 0, 1)
        ..scaleByDouble(scale, scale, 1, 1);
    });
  }

  Widget _nodeAt(MapSpot s, Device d, double side) {
    final r = side / 2 - _label / 2 - 20;
    final cx = side / 2 + s.x * r;
    final cy = side / 2 + s.y * r;
    return Positioned(
      left: cx - _label / 2,
      top: cy - _node / 2,
      width: _label,
      child: _MapNode(device: d, size: _node, onTap: () => _open(d)),
    );
  }

  Widget _legend(BuildContext context) {
    Widget item(UiStatus s, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: context.colors.tone(s).color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: context.text.bodySmall),
        ]);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 16,
      runSpacing: 6,
      children: [
        item(UiStatus.accent, 'Known'),
        item(UiStatus.warning, 'Not marked known'),
        item(UiStatus.neutral, 'Offline'),
      ],
    );
  }
}

UiStatus mapStatus(Device d) {
  if (!d.online && !d.isSelf) return UiStatus.neutral;
  if (!d.known && !d.isSelf && !d.isGateway) return UiStatus.warning;
  return UiStatus.accent;
}

class _MapNode extends StatelessWidget {
  const _MapNode({required this.device, required this.size, required this.onTap});

  final Device device;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = context.colors.tone(mapStatus(device));
    final center = device.isGateway;
    return Semantics(
      button: true,
      label: '${device.displayName}, ${device.ip}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: center ? tone.color : tone.soft,
                shape: BoxShape.circle,
                border: Border.all(color: tone.color, width: 2),
              ),
              child: Icon(deviceIcon(device.kind), size: size * 0.5, color: center ? tone.onColor : tone.onSoft),
            ),
            const SizedBox(height: 4),
            Text(
              device.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: context.text.labelSmall,
            ),
            Text(
              device.ip.split('.').last == device.ip ? device.ip : '.${device.ip.split('.').last}',
              maxLines: 1,
              textAlign: TextAlign.center,
              style: context.text.bodySmall?.copyWith(fontSize: 10.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lines from the router to each device (or from the center when there is none).
class _Links extends CustomPainter {
  _Links(this.spots, this.byIp, this.colors);

  final List<MapSpot> spots;
  final Map<String, Device> byIp;
  final UiColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.width;
    final r = side / 2 - _MapScreenState._label / 2 - 20;
    final c = Offset(side / 2, side / 2);
    final rings = spots.fold<int>(0, (m, s) => math.max(m, s.ring));
    final guide = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = colors.border;
    for (var i = 1; i <= rings; i++) {
      canvas.drawCircle(c, r * i / rings, guide);
    }
    for (final s in spots) {
      if (s.ring == 0) continue;
      final d = byIp[s.ip]!;
      final p = Paint()
        ..strokeWidth = d.online ? 1.6 : 1
        ..color = d.online ? colors.tone(mapStatus(d)).color.withValues(alpha: 0.45) : colors.border;
      canvas.drawLine(c, c + Offset(s.x * r, s.y * r), p);
    }
  }

  @override
  bool shouldRepaint(_Links old) => old.spots != spots || old.colors != colors;
}
