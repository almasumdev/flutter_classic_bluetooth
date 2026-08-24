/// Flutter Classic Bluetooth: Bluetooth Classic (RFCOMM) communication plugin.
///
/// Provides a unified Dart API for discovering, pairing, and communicating
/// with Bluetooth Classic devices over RFCOMM across Android, iOS (MFi only),
/// Windows, macOS, and Linux.
///
/// ## Getting Started
///
/// ```dart
/// import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';
///
/// final bluetooth = FlutterClassicBluetooth();
/// ```
///
/// ## Core API
///
/// | Class | Purpose |
/// |---|---|
/// | [FlutterClassicBluetooth] | Main entry point: adapter, discovery, pairing, connection, server |
/// | [BtcDevice] | Represents a remote Bluetooth device |
/// | [BtcConnection] | Active RFCOMM connection with input/output streams |
/// | [BtcReconnectingConnection] | Self-healing connection that auto-reconnects |
/// | [BtcReconnectPolicy] | Backoff/retry settings for auto-reconnect |
/// | [BtcServerSocket] | Listens for incoming RFCOMM connections |
/// | [BtcStreamSink] | Ordered write sink for a connection |
/// | [BtcFrameSplitter] | Splits input into delimited frames (`.lines()` helper) |
/// | [BtcPlatformCapabilities] | Platform feature support matrix |
///
/// ## Enums
///
/// | Enum | Purpose |
/// |---|---|
/// | [BtcAdapterState] | Adapter on/off/transitioning states |
/// | [BtcBondState] | Device pairing state |
/// | [BtcDeviceType] | Classic, LE, or Dual-mode |
/// | [BtcConnectionState] | Connection lifecycle states |
/// | [BtcReconnectState] | Auto-reconnect link states |
/// | [BtcPermissionStatus] | Whether the app holds the required permissions |
///
/// ## Exceptions
///
/// All exceptions extend [BtcException]:
///
/// | Exception | When |
/// |---|---|
/// | [BtcUnsupportedException] | Feature not available on platform |
/// | [BtcPermissionException] | Permission denied |
/// | [BtcDisabledException] | Adapter is off |
/// | [BtcConnectionException] | Connection failed |
/// | [BtcWriteException] | Write failed |
/// | [BtcDiscoveryException] | Discovery failed to start |
/// | [BtcTimeoutException] | Operation timed out |
/// | [BtcAddressException] | Invalid MAC address |
/// | [BtcUuidException] | Invalid UUID |
///
/// ## Platform Support
///
/// | Feature | Android | iOS | Windows | macOS | Linux |
/// |---------|---------|-----|---------|-------|-------|
/// | Permissions | Yes | Yes | n/a(5) | n/a(5) | n/a(5) |
/// | Adapter state | Yes | Yes | Yes | Yes | Yes |
/// | Discovery | Yes | No | Yes | Yes | Yes |
/// | Paired devices | Yes | Yes(1) | Yes | Yes | Yes |
/// | Bond | Yes | No | Yes(2) | Yes(3) | No |
/// | Unbond | Yes | No | No(4) | Yes(3) | No |
/// | RFCOMM connect | Yes | Yes(1) | Yes | Yes | Yes |
/// | RFCOMM server | Yes | No | Yes | Yes | Yes |
/// | Enable/Disable | Yes | No | No | No | Yes(3) |
/// | Set discoverable | Yes | No | No | No | Yes |
///
/// (1) iOS requires MFi-certified accessories via ExternalAccessory framework.
/// (2) macOS pairs via IOBluetoothDevicePair and may show a system prompt.
/// (3) Linux uses the BlueZ D-Bus API (org.bluez); pairing a PIN/passkey device
///     needs a system pairing agent.
/// (4) macOS has no public API to remove a pairing; unpair via System Settings.
/// (5) Windows, macOS and Linux grant Bluetooth access at build time, through a
///     manifest entry, an entitlement or the system's D-Bus policy, so
///     `checkPermissions` reports `notRequired` and there is nothing to ask for.
///
/// ## Example
///
/// ```dart
/// // Ask for permissions at a moment the user expects it
/// if (await bluetooth.checkPermissions() == BtcPermissionStatus.denied) {
///   await bluetooth.requestPermissions();
/// }
///
/// // Discover and connect
/// final caps = await bluetooth.getPlatformCapabilities();
/// if (caps.canDiscoverDevices) {
///   bluetooth.discoveryResults.listen((device) {
///     print('Found: ${device.displayName}');
///   });
///   await bluetooth.startDiscovery();
/// }
///
/// // Connect to a device
/// final conn = await bluetooth.connect(
///   address: 'AA:BB:CC:DD:EE:FF',
///   uuid: '00001101-0000-1000-8000-00805F9B34FB',
/// );
/// conn.input.listen((data) => print('Received: $data'));
/// await conn.output.add(Uint8List.fromList([0x01, 0x02]));
/// await conn.finish();
/// ```
library;

export 'src/btc_uuid.dart';
export 'src/btc_frame_splitter.dart';
export 'src/btc_reconnecting_connection.dart';
export 'src/flutter_classic_bluetooth.dart';
export 'src/platform_interface.dart';
export 'src/method_channel.dart';
export 'src/models/btc_enums.dart';
export 'src/models/btc_exceptions.dart';
export 'src/models/btc_device.dart';
export 'src/models/btc_connection.dart';
export 'src/models/btc_reconnect_policy.dart';
export 'src/models/btc_stream_sink.dart';
export 'src/models/btc_server_socket.dart';
export 'src/models/btc_platform_capabilities.dart';
