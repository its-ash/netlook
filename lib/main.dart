import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import 'platform/net_channel.dart';
import 'screens/home_screen.dart';
import 'store/device_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await DeviceStore.load();
  runApp(NetlookApp(store: store, platform: const NetChannel()));
}

class NetlookApp extends StatelessWidget {
  const NetlookApp({super.key, required this.store, required this.platform});

  final DeviceStore store;
  final NetPlatform platform;

  @override
  Widget build(BuildContext context) {
    store.onKnownChanged = () => store.syncWatch(platform);
    return UiApp(
      title: 'Netlook',
      home: HomeScreen(store: store, platform: platform),
    );
  }
}
