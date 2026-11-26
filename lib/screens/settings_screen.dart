import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:theme/theme.dart';

import '../platform/net_channel.dart';
import '../store/device_store.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.store, required this.platform, required this.info});

  final DeviceStore store;
  final NetPlatform platform;
  final NetInfo? info;

  Future<void> _toggleWatch(BuildContext context, bool on) async {
    final net = info;
    if (on) {
      if (net == null) {
        context.showToast('Connect to your home Wi-Fi first.');
        return;
      }
      await Permission.notification.request();
      if (!context.mounted) return;
      final trust = await UiDialog.confirm(
        context,
        title: 'Watch ${net.ssid ?? net.key}?',
        message: 'Alerts are sent for devices not marked known. Mark everything currently listed as known, so only newcomers alert you?',
        confirmLabel: 'Mark as known',
        cancelLabel: 'Keep as is',
      );
      if (trust) await store.markAllKnown(net.key);
      await store.saveWatch(enabled: true, key: net.key, name: net.ssid ?? net.key);
    } else {
      await store.saveWatch(enabled: false);
    }
    await store.syncWatch(platform);
  }

  Future<void> _setInterval(int m) async {
    await store.saveWatch(enabled: store.watchEnabled, interval: m);
    await store.syncWatch(platform);
  }

  @override
  Widget build(BuildContext context) {
    return UiScaffold(
      appBar: const UiAppBar(title: 'Settings'),
      scrollable: true,
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UiListGroup(
              header: 'New device alerts',
              footer: 'While on, Netlook scans in the background on the saved network and notifies you about devices '
                  'you have not marked known. It only runs when your phone is on that network. '
                  'Android may delay checks to save battery, so the interval is approximate.',
              children: [
                UiSwitchTile(
                  'Alert me about new devices',
                  subtitle: store.watchEnabled ? 'Watching ${store.watchName ?? store.watchKey}' : 'Off',
                  icon: Icons.notifications_active_rounded,
                  value: store.watchEnabled,
                  onChanged: (v) => _toggleWatch(context, v),
                ),
                UiListTile(
                  'Check every',
                  icon: Icons.schedule_rounded,
                  enabled: store.watchEnabled,
                  trailing: SizedBox(
                    width: 210,
                    child: UiSegmentedControl<int>(
                      [
                        for (final m in DeviceStore.intervals) UiSegment(m, label: m < 60 ? '$m min' : '${m ~/ 60} h'),
                      ],
                      value: store.watchInterval,
                      size: UiSize.sm,
                      expand: true,
                      onChanged: store.watchEnabled ? _setInterval : null,
                    ),
                  ),
                ),
              ],
            ),
            const UiGap(UiSpace.lg),
            UiListGroup(
              header: 'Public IP',
              footer: 'The lookup asks ipinfo.io for your public IP, internet provider and approximate area. '
                  'It sends nothing else. When off, it runs only when you tap Look up on the home screen.',
              children: [
                UiSwitchTile(
                  'Look up when the app opens',
                  icon: Icons.public_rounded,
                  value: store.autoPublicIp,
                  onChanged: store.setAutoPublicIp,
                ),
              ],
            ),
            const UiGap(UiSpace.lg),
            const UiListGroup(
              header: 'Privacy',
              children: [
                UiListTile(
                  'Everything stays on this phone',
                  subtitle: 'Scans only talk to devices on your own network. Location is used only so Android '
                      'reveals the Wi-Fi name, never to find where you are. The internet is used only to check for app '
                      'updates and, when you ask, to look up your public IP.',
                  icon: Icons.lock_rounded,
                  iconStatus: UiStatus.success,
                  maxSubtitleLines: 6,
                ),
              ],
            ),
            const UiGap(UiSpace.lg),
            const UiAppearanceSection(),
            const UiGap(UiSpace.lg),
            const UiUpdateSection(storeId: 'netlook'),
            const UiGap(UiSpace.lg),
            const UiDeveloperSection(),
          ],
        ),
      ),
    );
  }
}
