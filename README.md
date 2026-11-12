# Netlook

See who is on your Wi-Fi.

**[Website](https://netlook.itsash.in)** · **[Download APK](https://github.com/its-ash/netlook/releases/latest/download/netlook.apk)** · Get it in **[Ash Store](https://store.itsash.in)**

## Features

- Scans your current Wi-Fi subnet (up to a /22, 1022 addresses) with ICMP-style and TCP probes on common ports, with a progress bar.
- Names devices from reverse DNS, NetBIOS, mDNS / DNS-SD (Google Cast, AirPlay, printers, HomeKit, Spotify Connect, SMB) and UPnP / SSDP.
- Guesses the device type from open ports and services: router, printer, TV or cast device, camera, Apple device, computer and more.
- Wi-Fi header with SSID, your IP, gateway and DNS.
- Name your devices, mark them as known, see first and last seen, open ports and services, and run a ping test.
- Optional new-device alerts: a background check every 30, 60 or 120 minutes on your saved network.
- Everything stays on your phone. No account, no analytics.

Android 10+ does not let apps read the ARP table or other devices' MAC addresses, so Netlook cannot show vendors. Devices are told apart by IP, names and services.

## Install

- **Ash Store**: install [Ash Store](https://store.itsash.in) once, then install and update Netlook from it.
- **APK**: download the [latest APK](https://github.com/its-ash/netlook/releases/latest/download/netlook.apk) on your phone and open it. Allow your browser to install unknown apps if Android asks.

Requires Android 8.0 (API 26) or newer.

## Develop

Needs Flutter ≥ 3.44 and the shared theme package at `../theme`.

```bash
make run      # run on a connected device
make build    # release APK
make test     # flutter analyze + flutter test
make deploy   # bump version, build, tag, push, GitHub release (see store.mk)
```

## Release

`make deploy` follows the Ash Store kit (`store.mk`, `store.json`): it bumps the
version in `pubspec.yaml`, builds, commits, tags `vX.Y.Z`, pushes, and publishes
a GitHub release with `netlook.apk`. Ash Store and the website pick up the new
version from that release.

## Project layout

```
lib/core/       subnet math, port/service type guessing, SSDP and NetBIOS parsing (pure Dart, tested)
lib/scan/       scanner: sweep, names, mDNS, SSDP
lib/platform/   method channel to Kotlin
lib/store/      devices per network, alert settings
lib/screens/    home, device detail, settings
android/app/src/main/kotlin/com/itsash/netlook/
                network info, NSD, multicast lock, WorkManager new-device check
test/           unit tests
```

## License

All rights reserved.

Built by [itsash.in](https://itsash.in).
