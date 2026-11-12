# Netlook (package: netlook / com.itsash.netlook)

Shows who is on your Wi-Fi. Scans the current subnet, identifies devices by IP,
discovered names, services and open ports, lets the user label devices and mark
them "known", and can alert about new devices in the background.

**Hard limit:** Android 10+ apps cannot read the ARP table or other devices'
MACs. There is no vendor-by-MAC and the UI must not pretend otherwise. Device
identity is the IP (a DHCP change can make a device look new).

## Code layout

- `lib/core/`: pure Dart, unit tested in `test/`. Add a test for every change.
  - `subnet.dart`: IPv4 parse/format, `Subnet` (network, `hosts()`, key
    `a.b.c.0/p`, scan capped to /22 around the phone), `compareIps`.
  - `device_guess.dart`: `DeviceType`, `probePorts`, port names, DNS-SD service
    labels, `guessType`.
  - `ssdp.dart`: M-SEARCH, response and UPnP description XML parsing.
  - `netbios.dart`: NBSTAT query and response parsing.
  - `device.dart`: `Device` (json, `absorb`), `mergeScan`.
  - `ping_stats.dart`, `pool.dart` (`forEachLimited`).
- `lib/scan/scanner.dart`: `NetScanner.scan`: host sweep (Kotlin `isReachable`
  + TCP connects, refused = alive), reverse DNS, NetBIOS (one UDP socket),
  NSD results, SSDP (UDP multicast + description fetch, LAN hosts only).
- `lib/platform/net_channel.dart`: `NetPlatform` interface and `NetChannel`
  over `com.itsash.netlook/net` (`networkInfo`, `multicast`, `ping`, `nsd`,
  `watch`).
- `lib/store/device_store.dart`: devices per network key, alert settings
  (shared_preferences); `syncWatch` pushes settings and known IPs to Kotlin.
- `lib/screens/`: `home_screen` (Wi-Fi header, scan, list, settings icon),
  `device_screen`, `settings_screen` (alerts, privacy, `UiAppearanceSection`,
  `UiUpdateSection(storeId: 'netlook')`, `UiDeveloperSection`).
- `android/app/src/main/kotlin/com/itsash/netlook/`: `MainActivity.kt`
  (channel, multicast lock), `NetInfoReader.kt` (LinkProperties, SSID only with
  location permission), `NsdBrowser.kt`, `NetWatch.kt` (WorkManager periodic
  worker, a lightweight native subnet probe, notification; same network key
  format and /22 cap as Dart; keeps an "alerted" set so a device alerts once).

## Commands

- `make run`, `make build` (release APK), `make test` (`flutter analyze` +
  `flutter test`), `make clean`.
- Icon: SVG sources in `assets/icon/` (`logo`, `logo_foreground`,
  `logo_background`), `rsvg-convert -w 1024 -h 1024` to `*-1024.png`, then
  `dart run flutter_launcher_icons`.

## Conventions

- minSdk 26. UI only from the shared `theme` package (`../theme`).
- Permissions: `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`,
  `CHANGE_WIFI_MULTICAST_STATE`, `ACCESS_FINE_LOCATION` (only to read the SSID),
  `POST_NOTIFICATIONS`.
- Background alerts use the gateway/subnet key, not the SSID (SSID is not
  readable in the background without background location).

## Release (Ash Store)

- `store.json` (id `netlook`, repo its-ash/netlook), `store.mk`, `index.html`
  + `CNAME` (`netlook.itsash.in`). See `../ash-store/store-kit/STORE.md`.
- `make deploy` = bump version → build → commit, tag `vX.Y.Z`, push → GitHub
  release with `netlook.apk` → topics, homepage, Pages. Never create releases,
  tags or asset names by hand.
- Do not edit `store.mk` here. Edit `../ash-store/store-kit/store.mk`, then run
  `make store-sync` at the workspace root.
