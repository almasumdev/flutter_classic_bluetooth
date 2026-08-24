## 1.0.0

First stable release. The API is now settled, and anything breaking waits for
2.0.0.

### New

- **Permission API.** `checkPermissions()` reports the current status without
  prompting, `requestPermissions()` asks for what the platform requires, and
  `openAppSettings()` opens this app's settings page. The new
  `BtcPermissionStatus` enum has four values: `granted`, `denied`,
  `permanentlyDenied`, and `notRequired`.
- Permissions were previously requested implicitly, as a side effect of calling
  something that needed one. That still happens, so no existing code has to
  change. What was missing was any way to ask on your own terms: to show a
  reason before the system dialog, to ask during onboarding rather than at the
  first scan, or to tell a recoverable refusal from a permanent one.
- `permanentlyDenied` is detected properly rather than guessed. On Android,
  `shouldShowRequestPermissionRationale` reads the same before the first prompt
  as it does after a permanent refusal, so the plugin records that it has asked
  and uses that to tell the two apart. On iOS the answer comes from
  `CBManager.authorization`, where any refusal is permanent.
- Windows, macOS and Linux report `notRequired`: they grant Bluetooth access at
  build time through a manifest entry, an entitlement or the system's D-Bus
  policy, so there is nothing to ask for. Branching on the status rather than on
  the platform name gives one code path for all five.

### Changed

- `FlutterClassicBluetoothPlatform` gained three methods. They have default
  implementations, so a platform class that `extends` it keeps working. A class
  that `implements` it must add them; `plugin_platform_interface` asks
  implementers to extend for exactly this reason.
- The documentation site gained a permissions guide at
  https://flutter-classic-bluetooth.web.app/bluetooth-permissions.

## 0.1.10

Documentation and discoverability. No API or behaviour change.

### Changed

- Added a documentation website at https://flutter-classic-bluetooth.web.app,
  with task-based guides for permissions and platform setup, scanning,
  connecting, sending and receiving data, running an RFCOMM server, ESP32,
  HC-05 and Arduino, Bluetooth thermal printers, pairing, the desktop
  platforms, and troubleshooting. Linked from the package page via the
  `documentation` field, and from the README.

## 0.1.9

### Fixed
* `connect(timeout: ...)` no longer leaves a connection behind when the native
  attempt finishes after the deadline. A native connect cannot be cancelled, so
  one that succeeded late kept an open socket and two event channels that
  nothing in Dart could reach. Retrying in a loop left another one behind every
  time, until the adapter stopped accepting new connections. A late attempt is
  now closed and released for you.

### Changed
* Split the test suite into one file per area (plugin, method channel, models,
  connection, frame splitting, reconnect) sharing a single mock platform.
  Tests only; no change to the package.

## 0.1.8

### Changed
* New package logo.
* Tuned pub.dev topics and description for discoverability. No code changes.

## 0.1.7

### Fixed
* Windows: discovery result and state events are now delivered on the platform
  thread. They were being sent from the background discovery thread, which made
  Flutter warn about non-platform-thread channel messages and could drop events.
  Thanks to @translibrius for the report (#6).

## 0.1.6

### Changed
* Reworded the package description and swapped the `iot` topic for `printer` so
  developers searching pub.dev for thermal printer support can find the plugin.
  Metadata only; no API or behaviour changes.

## 0.1.5

### Added
* **Physical disconnect detection** (Android & iOS): when a connected device
  suddenly goes away (printer powered off, accessory unplugged, out of range),
  the plugin now detects it immediately, closes the dead connection, and emits
  `disconnected` on the connection's state stream so UIs and reconnect logic can
  react instead of the link appearing healthy. Android listens for
  `ACTION_ACL_DISCONNECTED`; iOS observes `EAAccessoryDidDisconnect`. Thanks to
  [@abbiyuarsyah](https://github.com/abbiyuarsyah).

### Fixed
* An ACL disconnect tears down the whole physical link, so all connections to
  the departed device are now closed, not just the first match (Android & iOS).
* iOS emits the terminal `disconnected` state exactly once, even when the stream
  delegate and the accessory-disconnect notification both fire for the same
  disconnect.
* iOS removes its `EAAccessoryDidDisconnect` observer on teardown.

## 0.1.4

### Fixed
* **iOS**: skip MAC-address and UUID format validation on iOS. The
  ExternalAccessory (MFi) framework hides the Bluetooth MAC address and exposes
  accessories by an opaque identifier, so the colon-separated MAC and standard
  UUID checks wrongly rejected valid iOS values. Validation still applies on all
  other platforms. Thanks to [@abbiyuarsyah](https://github.com/abbiyuarsyah).

## 0.1.3

### Added
* **Line / frame reading** for serial data: `Stream<Uint8List>.lines()` and
  `.frames()` extensions plus the `BtcFrameSplitter` transformer reassemble
  delimiter-terminated messages that span multiple `input` chunks. `.lines()`
  splits on `\n`, strips a trailing `\r`, and decodes to `String`, so ESP32 /
  HC-05 / Arduino serial output reads cleanly with `connection.input.lines()`.
  A `.decoded()` helper streams multi-byte-safe text.
* **Request/response**: `BtcConnection.sendAndReceive()` (and the same on
  `BtcReconnectingConnection`) writes a command and returns the first response
  line (or the first line matching a `where` predicate) with framing and a
  timeout handled for you. Ideal for AT-command devices.
* `BtcStreamSink.writeLine()` / `BtcReconnectingConnection.sendLine()`: write
  text with a trailing newline (CRLF by default).
* One-shot `FlutterClassicBluetooth.scan()`: starts discovery, collects results
  for a timeout (de-duplicated and merged), stops, and returns them sorted by
  signal strength. Plus `BtcDevice.mergedWith()` to combine repeated sightings.
* `BtcReconnectingConnection` now exposes `attempts` and `lastError` for UIs that
  show reconnect progress.
* **Connection RSSI (macOS)**: `BtcConnection.readRssi()` reads the live signal
  strength of an open link via `IOBluetoothDevice`. Gated by the new
  `BtcPlatformCapabilities.canReadConnectionRssi` flag; Android, iOS, Windows and
  Linux throw `BtcUnsupportedException` (no public Classic API for connection
  RSSI). Discovery-time RSSI stays available everywhere on `BtcDevice.rssi`.
* **Linux**: the plugin registers an auto-accepting BlueZ pairing agent
  (`org.bluez.Agent1`), so Secure Simple Pairing ("just works") devices (ESP32,
  most HC-05/06) pair from `bondDevice()` without a desktop dialog. Devices that
  require typing a PIN/passkey still need a system agent.

## 0.1.2

### Added
* **Auto-reconnect**: `connectWithReconnect()` returns a `BtcReconnectingConnection`
  that transparently re-establishes the link when it drops, with a configurable
  `BtcReconnectPolicy` (exponential backoff, max attempts, per-attempt timeout).
  Its `input` and `state` streams are stable across reconnects, so you subscribe
  once. New `BtcReconnectState` enum.

### Changed
* Discoverability: lead the package `description`, README title and opening with
  the terms developers actually search (Bluetooth Classic, RFCOMM/SPP, serial,
  ESP32, HC-05) so the package surfaces for those queries.
* Docs: add a **Roadmap** section to the README, a checked list of shipped
  capabilities plus planned items.

## 0.1.1

Reliability and completeness pass across all five platforms, plus API ergonomics.

### Added
* `BtcUuid.spp`, and `connect()` / `startServer()` now default `uuid` to it. The
  common case is just `connect(address: ...)` (HC-05/06, ESP32, Arduino, ...).
* `connect()` gains an optional `timeout` (throws `BtcTimeoutException`).
* `BtcConnection.stateStream` emits `disconnecting` → `disconnected` on `finish()`/`close()`.
* `BtcStreamSink` gains `writeString`, `writeBytes`, `addStream` and `allSent`.
* `BtcDiscoveryException` for `discoveryFailed` errors.

### Fixed
* **Android**: marshal method/event-channel work to the main thread; shared atomic
  connection ids; receivers emit an initial snapshot and use the API 34
  exported-receiver flag; no more orphaned permission/activity futures.
* **Windows**: register the per-connection/server/`bond_state` event channels
  (inbound data was dropped); deliver accepted clients; publish an SDP record;
  honor `secure`; surface `WSAStartup` failure; `setDiscoverable` via
  `BluetoothEnableDiscovery`.
* **Linux**: discovery, adapter state/power, discoverability, paired-device listing
  and pairing now run over the **BlueZ D-Bus API** (`org.bluez`) as the primary
  path, so they work for an **unprivileged** user (no root / CAP_NET_RAW).
  Discovery is event-driven via BlueZ signals (BR/EDR-filtered) with live adapter
  on/off; raw HCI is an automatic fallback. Connect/server/data use AF_BLUETOOTH
  RFCOMM, with the channel resolved from the UUID via SDP. Bundled GoogleTest
  bumped to v1.15.2 so the example configures on CMake 4.x.
* **macOS**: device discovery, accepted-client delivery, async connect/write,
  main-thread events, and pairing via `IOBluetoothDevicePair` (unpair via System
  Settings).
* **iOS**: real adapter-state stream via CoreBluetooth; `isEnabled` from the radio
  state with an MFi-accessory fallback.

### Changed
* Capability flags and the documentation tables reflect each platform's real support.
* SDK constraint set to `>=3.3.0 <4.0.0`.

> Note: Android, Windows and Linux are verified on-device. macOS native code is
> reviewed but should be compiled on macOS before production use.

## 0.1.0

* Initial release.
* Unified Dart API for Bluetooth Classic (RFCOMM) communication.
* **Android**: Full support (discovery, pairing, connect, server, discoverability).
* **Windows**: Discovery, pairing, connect, server via Winsock2/AF_BTH.
* **macOS**: Discovery, pairing, connect, server via IOBluetooth.
* **Linux**: Discovery, connect, server via BlueZ/RFCOMM. Pairing requires external tools.
* **iOS**: MFi accessory support via ExternalAccessory framework.
* Platform capabilities API for runtime feature detection.
* Multiple simultaneous RFCOMM connections.
* Stream-based data I/O with `BtcConnection`.
* Typed exception hierarchy (`BtcException` and subtypes).
* Example app with 7 screens demonstrating all features.
