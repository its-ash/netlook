import 'package:flutter/material.dart';

import '../core/device_guess.dart';

IconData deviceIcon(DeviceType t) => switch (t) {
      DeviceType.router => Icons.router_rounded,
      DeviceType.phone => Icons.smartphone_rounded,
      DeviceType.apple => Icons.phone_iphone_rounded,
      DeviceType.tv => Icons.tv_rounded,
      DeviceType.speaker => Icons.speaker_rounded,
      DeviceType.printer => Icons.print_rounded,
      DeviceType.camera => Icons.videocam_rounded,
      DeviceType.computer => Icons.computer_rounded,
      DeviceType.smartHome => Icons.home_rounded,
      DeviceType.mobile => Icons.tablet_android_rounded,
      DeviceType.console => Icons.sports_esports_rounded,
      DeviceType.storage => Icons.storage_rounded,
      DeviceType.unknown => Icons.devices_other_rounded,
    };
