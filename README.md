<p align="center">
  <a href="https://pub.dev/packages/flutter_classic_bluetooth"><img src="https://img.shields.io/pub/v/flutter_classic_bluetooth.svg" alt="pub version"></a>
  <a href="https://pub.dev/packages/flutter_classic_bluetooth/score"><img src="https://img.shields.io/pub/points/flutter_classic_bluetooth" alt="pub points"></a>
  <a href="https://pub.dev/packages/flutter_classic_bluetooth"><img src="https://img.shields.io/pub/likes/flutter_classic_bluetooth" alt="pub likes"></a>
  <a href="https://github.com/almasumdev/flutter_classic_bluetooth/stargazers"><img src="https://badgen.net/github/stars/almasumdev/flutter_classic_bluetooth?icon=github" alt="GitHub stars"></a>
  <a href="https://github.com/almasumdev/flutter_classic_bluetooth/network/members"><img src="https://badgen.net/github/forks/almasumdev/flutter_classic_bluetooth?icon=github" alt="GitHub forks"></a>
  <a href="https://github.com/almasumdev/flutter_classic_bluetooth/issues"><img src="https://badgen.net/github/open-issues/almasumdev/flutter_classic_bluetooth?icon=github" alt="GitHub issues"></a>
  <a href="https://github.com/almasumdev/flutter_classic_bluetooth/actions/workflows/ci.yml"><img src="https://github.com/almasumdev/flutter_classic_bluetooth/actions/workflows/ci.yml/badge.svg" alt="CI status"></a>
  <a href="https://github.com/almasumdev/flutter_classic_bluetooth/commits/main"><img src="https://badgen.net/github/last-commit/almasumdev/flutter_classic_bluetooth?icon=github" alt="Last commit"></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://dart.dev"><img src="https://img.shields.io/badge/Dart-3.3+-0175C2?logo=dart" alt="Dart"></a>
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-3.3+-02569B?logo=flutter" alt="Flutter"></a>
</p>

# Bluetooth Classic Serial (RFCOMM/SPP) Plugin for Flutter

**flutter_classic_bluetooth** is a Flutter plugin for **Bluetooth Classic
serial communication over RFCOMM (the Serial Port Profile, SPP)**. It lets you
**discover, pair, connect to, and exchange data with** Bluetooth Classic devices
(**ESP32**, **ESP8266**, **Arduino** boards, **HC-05** / **HC-06** modules,
barcode scanners, thermal printers, OBD-II adapters, and other serial / UART
peripherals) from a single Dart API on **Android, Windows, macOS, Linux, and
iOS (MFi)**. Connections are exposed as Dart streams, so reading and writing
bytes feels like any other `Stream`/`Sink`.

> 📘 **[Documentation](https://flutter-classic-bluetooth.web.app)**: guides for
> [permissions and setup](https://flutter-classic-bluetooth.web.app/bluetooth-permissions),
> [scanning](https://flutter-classic-bluetooth.web.app/scan-bluetooth-devices),
> [connecting](https://flutter-classic-bluetooth.web.app/connect-bluetooth-device),
> [sending and receiving data](https://flutter-classic-bluetooth.web.app/send-receive-data),
> [running a server](https://flutter-classic-bluetooth.web.app/rfcomm-server),
> [ESP32](https://flutter-classic-bluetooth.web.app/esp32-bluetooth),
> [HC-05 and Arduino](https://flutter-classic-bluetooth.web.app/hc-05-arduino),
> [thermal printers](https://flutter-classic-bluetooth.web.app/bluetooth-thermal-printer),
> [pairing](https://flutter-classic-bluetooth.web.app/pair-devices),
> [desktop platforms](https://flutter-classic-bluetooth.web.app/desktop-bluetooth) and
> [troubleshooting](https://flutter-classic-bluetooth.web.app/troubleshooting).

> ⭐ **Find this useful?** [Star it on GitHub](https://github.com/almasumdev/flutter_classic_bluetooth)
> and 👍 [like it on pub.dev](https://pub.dev/packages/flutter_classic_bluetooth).
> It helps other Flutter developers find a maintained Bluetooth Classic plugin.

## Overview

flutter_classic_bluetooth speaks **RFCOMM/SPP**, the classic Bluetooth serial
transport, not Bluetooth Low Energy (BLE). It wraps each platform's native
stack (Android `BluetoothSocket`, Windows Winsock2 `AF_BTH`, Linux BlueZ
RFCOMM sockets, macOS IOBluetooth, iOS ExternalAccessory) behind one consistent
Dart interface. You can act as a **client** (connect out to a device) or as a
**server** (advertise an SDP service and accept incoming connections), run
several connections at once, and observe adapter, discovery, and bond state
through broadcast streams.

**What you can do with it:**

- Discover nearby devices and list paired/bonded devices.
- Connect over RFCOMM by MAC address + service UUID, then read and write a byte stream.
- Run an RFCOMM server that accepts incoming client connections.
- Pair/unpair devices, toggle the adapter, and make the device discoverable (where the platform allows).
- Query per-platform capabilities at runtime so your UI only offers what works.

## Table of contents

- [Key features](#key-features)
- [Platform support](#platform-support)
- [Roadmap](#roadmap)
- [Example](#example)
- [Other useful links](#other-useful-links)
- [Installation](#installation)
- [Platform setup](#platform-setup)
- [Getting started](#getting-started)
  - [Initialize and check support](#initialize-and-check-support)
  - [Request permissions](#request-permissions)
  - [The Android location trap](#the-android-location-trap)
  - [Discover nearby devices](#discover-nearby-devices)
  - [List paired devices](#list-paired-devices)
  - [Connect to a device](#connect-to-a-device)
  - [Receive data](#receive-data)
  - [Read line-by-line](#read-line-by-line)
  - [Send data](#send-data)
  - [Request / response (AT commands)](#request--response-at-commands)
  - [Watch the connection state](#watch-the-connection-state)
  - [Disconnect and dispose](#disconnect-and-dispose)
  - [Reconnect automatically](#reconnect-automatically)
  - [Run an RFCOMM server](#run-an-rfcomm-server)
  - [Pair and unpair](#pair-and-unpair)
  - [Adapter state and control](#adapter-state-and-control)
  - [Handle errors](#handle-errors)
- [FAQ](#faq)
- [Support and feedback](#support-and-feedback)
- [About](#about)
  - [Contributors](#contributors)

## Key features

A complete Bluetooth Classic (RFCOMM/SPP) client + server toolkit behind one
Dart API. Expand a group for details:

<details>
<summary><b>📡 Connectivity</b></summary>

- RFCOMM/SPP **client**: connect by address + service UUID, secure or insecure
- RFCOMM **server**: advertise an SDP service and accept incoming clients
- **Multiple simultaneous** connections, each with its own id
- Optional **connection timeout**
- Optional **auto-reconnect** with exponential backoff (`connectWithReconnect`)
- **Request/response**: `sendAndReceive()` writes a command and awaits its reply line

</details>

<details>
<summary><b>🔍 Discovery & pairing</b></summary>

- **Permission API**: check and request per operation, detect a permanent denial, and catch the Android location-toggle trap, with no extra package
- Device **discovery** with results and start/stop state streams, plus a one-shot `scan()`
- **Paired/bonded** device listing
- **Bond / unbond** devices and observe bond-state changes
- **Make discoverable** (where supported)

</details>

<details>
<summary><b>🔀 Streamed I/O</b></summary>

- Incoming bytes as a Dart `Stream<Uint8List>`
- **Line/frame reader**: `input.lines()` / `input.frames()` reassemble delimited messages across chunks
- Ordered write sink: `add`, `writeBytes`, `writeString`, `writeLine`, `addStream`, `allSent`
- Connection-state stream (`connecting` → `connected` → `disconnecting` → `disconnected`)

</details>

<details>
<summary><b>🧩 Adapter & capabilities</b></summary>

- Adapter **state stream**, name, and address
- **Enable/disable** the adapter (Android)
- Runtime **platform-capability** matrix so the UI adapts per platform

</details>

<details>
<summary><b>🛡️ Reliability</b></summary>

- Typed exception hierarchy: `BtcException` + subtypes
- Main-thread-safe event delivery on every platform
- Honest per-platform capability reporting (no dead code paths)

</details>

## Platform support

Bluetooth Classic capabilities differ by OS, so the plugin reports what each one
can actually do (also queryable at runtime via `getPlatformCapabilities()`):

| Feature | Android | Windows | macOS | Linux | iOS |
|---------|---------|---------|-------|-------|-----|
| Adapter state stream | ✅ | ✅ | ✅ | ✅ | ✅ |
| Discover devices | ✅ | ✅ | ✅ | ✅ | ❌ |
| Get paired devices | ✅ | ✅ | ✅ | ✅ | ✅¹ |
| Pair (bond) | ✅ | ✅ | ✅² | ✅³ | ❌ |
| Unpair (unbond) | ✅ | ✅ | ❌⁴ | ✅³ | ❌ |
| Connect (RFCOMM) | ✅ | ✅ | ✅ | ✅ | ✅¹ |
| Server mode | ✅ | ✅ | ✅ | ✅ | ❌ |
| Enable / Disable | ✅ | ❌ | ❌ | ✅³ | ❌ |
| Set discoverable | ✅ | ✅ | ❌ | ✅ | ❌ |

¹ iOS uses the ExternalAccessory framework, so only **MFi-certified** accessories are supported, and the `uuid` argument is treated as the MFi protocol string.<br/>
² macOS pairs via `IOBluetoothDevicePair` and may show a system pairing prompt.<br/>
³ Linux uses the BlueZ D-Bus API (`org.bluez`); pairing a device that needs a PIN/passkey requires a system pairing agent.<br/>
⁴ macOS has no public API to remove an existing pairing; unpair via System Settings.

## Roadmap

What's shipped and what's next. Completed items are checked; the rest is on the
list; [contributions](#support-and-feedback) welcome.

**Shipped**

- ✅ RFCOMM/SPP **client**: connect by address + UUID, secure/insecure, optional timeout
- ✅ RFCOMM **server**: advertise an SDP service and accept incoming clients
- ✅ **Multiple simultaneous** connections, each with its own id
- ✅ Device **discovery** with results and start/stop state streams
- ✅ **Paired/bonded** device listing
- ✅ **Pair / unpair** with a bond-state stream
- ✅ Adapter **state stream**, **enable/disable**, and **set discoverable**
- ✅ Streamed byte I/O: ordered write sink (`writeString` / `writeLine` / `writeBytes` / `addStream`)
- ✅ Line/frame reader: split serial input on a delimiter (`input.lines()` / `input.frames()`)
- ✅ Request/response helper: `sendAndReceive()` for AT-command / line protocols
- ✅ **Connection-state** lifecycle stream
- ✅ Runtime **platform-capability** matrix
- ✅ Typed **exception hierarchy** (`BtcException` + subtypes)
- ✅ `BtcUuid.spp` default: `connect(address: ...)` just works for serial devices
- ✅ Optional **auto-reconnect** with exponential backoff (`connectWithReconnect`)
- ✅ Linux **SSP pairing agent**: pair "just works" devices from `bondDevice()` with no desktop dialog
- ✅ **Five platforms**: Android, Windows, macOS, Linux, iOS (MFi)
- ✅ Linux via **BlueZ D-Bus**: discovery, adapter and pairing work without root
- ✅ **Connection RSSI** on macOS: read the live link signal strength with `connection.readRssi()`
- ✅ **Permission API**: per-operation `checkPermissions()` / `requestPermissions()`, permanent-denial detection, and location-toggle detection for Android 11 and below

**Planned**

- ⬜ Expanded on-device integration tests

**Not currently possible** (platform limits, tracked but blocked)

- ⛔ Connection RSSI on **Android, iOS & Windows**: no public Bluetooth Classic API (macOS is supported; Linux would require privileged raw HCI). Discovery-time RSSI is available everywhere via `BtcDevice.rssi`.
- ⛔ macOS programmatic unpair: no public Apple API

**Out of scope**, use a dedicated package instead: Bluetooth Low Energy (BLE),
and Web (Bluetooth Classic is not available in browsers).

## Example

A complete, runnable demo app lives in the
[`example/`](https://github.com/almasumdev/flutter_classic_bluetooth/tree/main/example)
directory, with screens for adapter control, device discovery, paired devices,
RFCOMM client/server, and the platform-capabilities matrix. Clone the repository
and run it, or copy any snippet from [Getting started](#getting-started) below.

## Other useful links

- [Documentation and guides](https://flutter-classic-bluetooth.web.app)
- [API reference](https://pub.dev/documentation/flutter_classic_bluetooth/latest/)
- [Source code on GitHub](https://github.com/almasumdev/flutter_classic_bluetooth)
- [Changelog](https://github.com/almasumdev/flutter_classic_bluetooth/blob/main/CHANGELOG.md)
- [Issue tracker](https://github.com/almasumdev/flutter_classic_bluetooth/issues)

## Installation

```bash
flutter pub add flutter_classic_bluetooth
```

Then import it:

```dart
import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';
```

## Platform setup

**Android**: add the Bluetooth permissions to `android/app/src/main/AndroidManifest.xml`:

```xml
<!-- Android 11 (API 30) and below -->
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
<!-- Android 12 (API 31) and above -->
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
```

**iOS**: declare the MFi protocol(s) and a usage string in `ios/Runner/Info.plist`:

```xml
<key>UISupportedExternalAccessoryProtocols</key>
<array>
  <string>com.example.spp</string>
</array>
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app communicates with Bluetooth accessories.</string>
```

**macOS**: add the Bluetooth entitlement to `macos/Runner/*.entitlements` and a
usage string to `Info.plist`:

```xml
<key>com.apple.security.device.bluetooth</key>
<true/>
```

**Linux**: install the GTK and BlueZ development packages the native plugin
builds against (Debian/Ubuntu shown; the build fails with a `gtk+-3.0` or
`bluetooth/bluetooth.h` CMake error if they're missing):

```bash
sudo apt-get install -y libgtk-3-dev libbluetooth-dev ninja-build cmake pkg-config clang
```

On Fedora use `gtk3-devel bluez-libs-devel ninja-build cmake clang`; on Arch,
`gtk3 bluez-libs ninja cmake clang`.

## Getting started

### Initialize and check support

```dart
final bluetooth = FlutterClassicBluetooth();

final supported = await bluetooth.isSupported();
final enabled = await bluetooth.isEnabled();
final caps = await bluetooth.getPlatformCapabilities();

if (caps.canDiscoverDevices) {
  // safe to call startDiscovery() on this platform
}
```

### Request permissions

Ask for what the app actually uses. Android 12 split one Bluetooth permission
into three, so an app that only talks to a device the user already paired does
not have to ask for permission to scan:

```dart
// A printer app that works from the paired list.
final status = await bluetooth.checkPermissions(
  permissions: {BtcPermission.connect},
);
```

The default is `{BtcPermission.scan, BtcPermission.connect}`, which is what a
discover-then-connect app needs.

Every call still requests what it needs on its own, so the plugin works with no
permission code at all. Asking yourself just means you get to explain first,
instead of the system dialog appearing out of nowhere at the first scan:

```dart
switch (await bluetooth.checkPermissions()) {
  case BtcPermissionStatus.granted:
  case BtcPermissionStatus.notRequired:
    startScanning();

  case BtcPermissionStatus.denied:
    // The system will still prompt. Show a reason, then ask.
    if (await bluetooth.requestPermissions() == BtcPermissionStatus.granted) {
      startScanning();
    }

  case BtcPermissionStatus.permanentlyDenied:
    // The system has stopped asking. Only settings can change it.
    await bluetooth.openAppSettings();
}
```

What each value maps to per platform:

| | Android 12+ (API 31+) | Android 7 to 11 (API 24 to 30) | iOS | Windows, macOS, Linux |
|---|---|---|---|---|
| `scan` | `BLUETOOTH_SCAN` | fine location on API 29+, coarse below, **plus the location toggle** | one Bluetooth grant | `notRequired` |
| `connect` | `BLUETOOTH_CONNECT` | nothing at runtime | one Bluetooth grant | `notRequired` |
| `advertise` | `BLUETOOTH_ADVERTISE` | nothing at runtime | one Bluetooth grant | `notRequired` |

`notRequired` means the platform decided access at build time, through a
manifest entry, an entitlement or the system's D-Bus policy. Treat it exactly
like `granted`.

### The Android location trap

On Android 11 and below, discovery needs the **system location toggle switched
on**, not just the permission granted. With the permission held and the toggle
off, `startDiscovery` succeeds, reports no error, and never finds anything.
That is the least obvious way Bluetooth fails on Android, so it is worth
checking for by name:

```dart
if (await bluetooth.isLocationServiceRequired() &&
    !await bluetooth.isLocationServiceEnabled()) {
  // Explain, then offer the settings screen. There is no in-app prompt for
  // this; it is a system-wide setting.
  await bluetooth.openLocationSettings();
}
```

Both report harmless values everywhere the trap does not exist, so the check
above reads correctly on all five platforms.

### Discover nearby devices

One-shot: scan for a fixed window and get the de-duplicated list back, sorted
by signal strength:

```dart
final devices = await bluetooth.scan(timeout: const Duration(seconds: 8));
for (final d in devices) {
  print('${d.displayName} (${d.address}) ${d.rssi ?? ''}');
}
```

Live: stream results as they arrive:

```dart
final sub = bluetooth.discoveryResults.listen((device) {
  print('Found: ${device.displayName} (${device.address})');
});

await bluetooth.startDiscovery();
// ...later
await bluetooth.stopDiscovery();
await sub.cancel();
```

### List paired devices

```dart
final devices = await bluetooth.getPairedDevices();
for (final device in devices) {
  print('${device.displayName} - ${device.address} [${device.bondState.name}]');
}
```

### Connect to a device

```dart
// SPP is the default. For HC-05/06, ESP32, Arduino, etc. this is all you need:
final connection = await bluetooth.connect(address: 'AA:BB:CC:DD:EE:FF');
print('Connected: id=${connection.id}');

// Override the UUID and tune the attempt only when you need to:
final custom = await bluetooth.connect(
  address: 'AA:BB:CC:DD:EE:FF',
  uuid: BtcUuid.spp, // or any service UUID string
  secure: true,
  timeout: const Duration(seconds: 15), // optional
);
```

### Receive data

```dart
connection.input.listen(
  (Uint8List data) => print('Received ${data.length} bytes: $data'),
  onDone: () => print('Remote closed the connection'),
);
```

### Read line-by-line

Serial devices send delimited text, but RFCOMM (like any stream) doesn't
preserve message boundaries. `lines()` reassembles complete lines across chunks.
It splits on `\n`, strips a trailing `\r`, and decodes to `String`:

```dart
connection.input.lines().listen((line) => print('> $line'));

// Custom framing: split on any delimiter, keep raw bytes.
connection.input
    .frames(delimiter: const [0x03]) // e.g. ETX-terminated frames
    .listen((frame) => print('frame: ${frame.length} bytes'));
```

Works the same on an auto-reconnecting link: `link.input.lines()`.

### Send data

```dart
// Raw bytes
await connection.output.add(Uint8List.fromList([0x01, 0x02, 0x03]));

// Convenience helpers
await connection.output.writeBytes([0x04, 0x05]);
await connection.output.writeString('AT+RESET\r\n');

// A whole line (appends CRLF by default)
await connection.output.writeLine('AT');

// Wait until everything queued so far has been written
await connection.output.allSent;
```

### Request / response (AT commands)

`sendAndReceive` writes a command and returns the first response line (framing
and timeout handled for you), the usual pattern for AT-command modules:

```dart
final version = await connection.sendAndReceive('AT+GMR');
final ok = await connection.sendAndReceive(
  'AT',
  where: (line) => line == 'OK', // skip echoes; return the line you want
  timeout: const Duration(seconds: 2),
);
// Throws BtcTimeoutException if nothing matches in time.
```

### Watch the connection state

```dart
connection.stateStream.listen((state) {
  print('State: ${state.name}'); // connected, disconnecting, disconnected, ...
});

print(connection.isConnected); // true while connected
```

### Disconnect and dispose

```dart
await connection.finish(); // flush pending writes, then disconnect
// or: await connection.close(); // disconnect immediately

connection.dispose(); // always release resources when done
```

### Reconnect automatically

For long-lived links to a flaky device, `connectWithReconnect` keeps the
connection alive across drops. Its `input` and `state` streams are **stable**:
subscribe once and keep receiving data as the underlying connection is replaced.

```dart
final link = bluetooth.connectWithReconnect(
  address: 'AA:BB:CC:DD:EE:FF',
  policy: const BtcReconnectPolicy(
    maxAttempts: null, // retry forever (default)
    initialBackoff: Duration(seconds: 1),
    maxBackoff: Duration(seconds: 30),
  ),
);

link.state.listen((s) => print('Link: ${s.name}')); // connecting/connected/reconnecting/...
link.input.listen((bytes) => print('RX ${bytes.length} bytes'));

if (link.isConnected) await link.sendString('PING\r\n');

// ...when done
await link.close(); // stop reconnecting and release everything
```

### Run an RFCOMM server

```dart
final server = await bluetooth.startServer(
  serviceName: 'MyService',
  uuid: BtcUuid.spp, // optional, SPP is the default
  secure: true,
);

server.connections.listen((client) {
  print('Client connected: ${client.address}');
  client.input.listen((data) => client.output.writeString('echo: '));
});

// ...later
await server.close();
```

### Pair and unpair

```dart
if (caps.canBondDevices) {
  final ok = await bluetooth.bondDevice('AA:BB:CC:DD:EE:FF');
  print('Bonded: $ok');
}

bluetooth.bondState('AA:BB:CC:DD:EE:FF').listen((state) {
  print('Bond state: ${state.name}');
});

await bluetooth.unbondDevice('AA:BB:CC:DD:EE:FF');
```

### Adapter state and control

```dart
bluetooth.adapterState.listen((state) {
  print('Adapter: ${state.name}'); // on, off, turningOn, ...
});

if (caps.canEnableBluetooth) {
  await bluetooth.enableBluetooth(); // Android: shows the system dialog
}

if (caps.canSetDiscoverable) {
  await bluetooth.setDiscoverable(120); // seconds
}
```

### Handle errors

```dart
try {
  await bluetooth.connect(address: addr, uuid: uuid);
} on BtcUnsupportedException catch (e) {
  print('${e.feature} not supported on ${e.platform}');
} on BtcDisabledException {
  print('Turn on Bluetooth first');
} on BtcTimeoutException {
  print('Connection timed out');
} on BtcConnectionException catch (e) {
  print('Connection failed: ${e.message}');
} on BtcException catch (e) {
  print('Bluetooth error: ${e.message}');
}
```

Every failure throws a typed `BtcException` (or a subtype): `BtcUnsupportedException`,
`BtcPermissionException`, `BtcDisabledException`, `BtcConnectionException`,
`BtcWriteException`, `BtcDiscoveryException`, `BtcTimeoutException`,
`BtcAddressException`, and `BtcUuidException`.

## FAQ

**Is this Bluetooth Classic or Bluetooth Low Energy (BLE)?**
Bluetooth **Classic**: RFCOMM/SPP serial communication. For BLE, use a
BLE-specific package; this plugin targets classic serial peripherals like
ESP32, HC-05/HC-06, printers, and scanners.

**Does it work with ESP32, ESP8266, Arduino, and HC-05/HC-06 modules?**
Yes. Any device that exposes a Bluetooth Classic **RFCOMM/SPP serial** profile
works: an **ESP32** using `BluetoothSerial`, an **Arduino** or **ESP8266** wired
to an **HC-05**/**HC-06** module, and other UART-over-Bluetooth peripherals
(thermal printers, barcode scanners, OBD-II adapters). Pair the device, then
just `connect(address: ...)`; the SPP UUID (`BtcUuid.spp`) is used by default.

**Which platforms are supported?**
Android, Windows, macOS, and Linux for full client/server RFCOMM; iOS supports
only **MFi-certified** accessories via the ExternalAccessory framework (no
discovery or server mode). See [Platform support](#platform-support).

**Why does iOS behave differently?**
Apple restricts general Bluetooth Classic access to MFi-certified accessories.
On iOS the `uuid` you pass to `connect()` is treated as the MFi protocol string,
and discovery/pairing/server features are unavailable by platform design.

**Can I have several connections open at once?**
Yes. Each `connect()` (and each accepted server client) returns an independent
`BtcConnection` with its own input/output streams.

**How do I know if a feature works on the current device?**
Call `getPlatformCapabilities()` and check the matching flag (e.g.
`canDiscoverDevices`, `canCreateServer`) before invoking it. The plugin reports
capabilities honestly per platform.

**How does pairing work on macOS and Linux?**
On macOS, `bondDevice` pairs via `IOBluetoothDevicePair` (which may show a system
prompt for PIN/passkey devices); removing a pairing has no public API, so unpair
through System Settings. On Linux, `bondDevice`/`unbondDevice` use the BlueZ
D-Bus API directly; devices that require a PIN or passkey additionally need a
system pairing agent (e.g. a running desktop Bluetooth applet).

## Support and feedback

- Found a bug or want a feature? Open an issue on the
  [issue tracker](https://github.com/almasumdev/flutter_classic_bluetooth/issues).
- Questions and ideas are welcome via
  [GitHub Discussions](https://github.com/almasumdev/flutter_classic_bluetooth/discussions).
- Pull requests are welcome; start with the
  [contributing guide](https://github.com/almasumdev/flutter_classic_bluetooth/blob/main/CONTRIBUTING.md).
- To report a security issue privately, see the
  [security policy](https://github.com/almasumdev/flutter_classic_bluetooth/blob/main/SECURITY.md).

## About

flutter_classic_bluetooth is an open-source, MIT-licensed Flutter plugin for
Bluetooth Classic (RFCOMM/SPP) serial communication across Android, Windows,
macOS, Linux, and iOS (MFi), exposing native Bluetooth stacks through one
stream-based Dart API.

flutter_classic_bluetooth is created and owned by **Nurullah Al Masum**.

### Contributors

flutter_classic_bluetooth grows with its community, and every contributor is listed here:

<a href="https://github.com/almasumdev/flutter_classic_bluetooth/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=almasumdev/flutter_classic_bluetooth" alt="flutter_classic_bluetooth contributors"/>
</a>

Want to help? Pull requests are welcome; see [Support and feedback](#support-and-feedback).
