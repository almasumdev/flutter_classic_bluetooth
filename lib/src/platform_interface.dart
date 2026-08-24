import 'dart:typed_data';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'btc_uuid.dart';
import 'method_channel.dart';
import 'models/btc_enums.dart';
import 'models/btc_connection.dart';
import 'models/btc_device.dart';
import 'models/btc_server_socket.dart';
import 'models/btc_platform_capabilities.dart';

/// The interface that platform-specific implementations must implement.
///
/// Platform implementations should extend this class rather than implement it,
/// as new methods may be added in the future. Using `extends` ensures
/// forward compatibility.
///
/// {@category Platform}
abstract class FlutterClassicBluetoothPlatform extends PlatformInterface {
  FlutterClassicBluetoothPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterClassicBluetoothPlatform _instance =
      MethodChannelFlutterClassicBluetooth();

  /// The default instance of [FlutterClassicBluetoothPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterClassicBluetooth].
  static FlutterClassicBluetoothPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterClassicBluetoothPlatform]
  /// when they register themselves.
  static set instance(FlutterClassicBluetoothPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  // ── Permissions ───────────────────────────────────────────────────────

  /// Returns the status of [permissions] without prompting.
  Future<BtcPermissionStatus> checkPermissions(Set<BtcPermission> permissions) {
    throw UnimplementedError('checkPermissions() has not been implemented.');
  }

  /// Requests [permissions] and returns the status afterwards.
  Future<BtcPermissionStatus> requestPermissions(
      Set<BtcPermission> permissions) {
    throw UnimplementedError('requestPermissions() has not been implemented.');
  }

  /// Opens this app's system settings page.
  Future<bool> openAppSettings() {
    throw UnimplementedError('openAppSettings() has not been implemented.');
  }

  /// Whether scanning on this platform also needs the system location toggle.
  Future<bool> isLocationServiceRequired() {
    throw UnimplementedError(
        'isLocationServiceRequired() has not been implemented.');
  }

  /// Whether the system location toggle is currently on.
  Future<bool> isLocationServiceEnabled() {
    throw UnimplementedError(
        'isLocationServiceEnabled() has not been implemented.');
  }

  /// Opens the system location settings screen.
  Future<bool> openLocationSettings() {
    throw UnimplementedError(
        'openLocationSettings() has not been implemented.');
  }

  // ── Adapter ──────────────────────────────────────────────────────────

  /// Returns whether Bluetooth Classic is supported on this device.
  Future<bool> isSupported() {
    throw UnimplementedError('isSupported() has not been implemented.');
  }

  /// Returns whether the Bluetooth adapter is currently enabled.
  Future<bool> isEnabled() {
    throw UnimplementedError('isEnabled() has not been implemented.');
  }

  /// Requests the system to enable the Bluetooth adapter.
  ///
  /// Returns `true` if Bluetooth was successfully enabled or was already on.
  Future<bool> enableBluetooth() {
    throw UnimplementedError('enableBluetooth() has not been implemented.');
  }

  /// Requests the system to disable the Bluetooth adapter.
  ///
  /// Returns `true` if Bluetooth was successfully disabled or was already off.
  Future<bool> disableBluetooth() {
    throw UnimplementedError('disableBluetooth() has not been implemented.');
  }

  /// Returns the current adapter state as a stream that emits on changes.
  Stream<BtcAdapterState> adapterState() {
    throw UnimplementedError('adapterState() has not been implemented.');
  }

  /// Returns the local adapter's friendly name.
  Future<String?> getAdapterName() {
    throw UnimplementedError('getAdapterName() has not been implemented.');
  }

  /// Returns the local adapter's hardware address.
  Future<String?> getAdapterAddress() {
    throw UnimplementedError('getAdapterAddress() has not been implemented.');
  }

  // ── Discovery ────────────────────────────────────────────────────────

  /// Starts discovering nearby Bluetooth Classic devices.
  ///
  /// Results are delivered via [discoveryResults]. Discovery state changes
  /// are delivered via [discoveryState].
  Future<void> startDiscovery() {
    throw UnimplementedError('startDiscovery() has not been implemented.');
  }

  /// Stops an ongoing device discovery.
  Future<void> stopDiscovery() {
    throw UnimplementedError('stopDiscovery() has not been implemented.');
  }

  /// Returns whether a discovery scan is currently in progress.
  Future<bool> isDiscovering() {
    throw UnimplementedError('isDiscovering() has not been implemented.');
  }

  /// Stream that emits `true` when discovery starts and `false` when it stops.
  Stream<bool> discoveryState() {
    throw UnimplementedError('discoveryState() has not been implemented.');
  }

  /// Stream of devices found during discovery.
  Stream<BtcDevice> discoveryResults() {
    throw UnimplementedError('discoveryResults() has not been implemented.');
  }

  // ── Pairing ──────────────────────────────────────────────────────────

  /// Returns the list of currently paired/bonded devices.
  Future<List<BtcDevice>> getPairedDevices() {
    throw UnimplementedError('getPairedDevices() has not been implemented.');
  }

  /// Initiates pairing with the device at [address].
  ///
  /// Returns `true` if bonding succeeded.
  Future<bool> bondDevice(String address) {
    throw UnimplementedError('bondDevice() has not been implemented.');
  }

  /// Removes the bond with the device at [address].
  ///
  /// Returns `true` if the bond was successfully removed.
  Future<bool> unbondDevice(String address) {
    throw UnimplementedError('unbondDevice() has not been implemented.');
  }

  /// Stream of bond state changes for a specific device.
  Stream<BtcBondState> bondState(String address) {
    throw UnimplementedError('bondState() has not been implemented.');
  }

  // ── Connection ───────────────────────────────────────────────────────

  /// Connects to the device at [address] using the given [uuid].
  ///
  /// If [secure] is `true` (default), uses authenticated/encrypted RFCOMM.
  /// Returns a [BtcConnection] for reading/writing data.
  Future<BtcConnection> connect({
    required String address,
    String uuid = BtcUuid.spp,
    bool secure = true,
  }) {
    throw UnimplementedError('connect() has not been implemented.');
  }

  /// Disconnects the connection with the given [id].
  Future<void> disconnect(int id) {
    throw UnimplementedError('disconnect() has not been implemented.');
  }

  /// Writes [data] to the connection with the given [id].
  Future<void> write(int id, Uint8List data) {
    throw UnimplementedError('write() has not been implemented.');
  }

  // ── Server ───────────────────────────────────────────────────────────

  /// Creates an RFCOMM server socket listening on the given [uuid].
  ///
  /// [serviceName] is the SDP service name. If [secure] is `true`,
  /// uses authenticated/encrypted RFCOMM.
  Future<BtcServerSocket> startServer({
    required String serviceName,
    String uuid = BtcUuid.spp,
    bool secure = true,
  }) {
    throw UnimplementedError('startServer() has not been implemented.');
  }

  /// Stops the server with the given [id].
  Future<void> stopServer(int id) {
    throw UnimplementedError('stopServer() has not been implemented.');
  }

  // ── Discoverability ──────────────────────────────────────────────────

  /// Makes the local device discoverable for [durationSeconds].
  ///
  /// Returns `true` if the request was successful.
  Future<bool> setDiscoverable(int durationSeconds) {
    throw UnimplementedError('setDiscoverable() has not been implemented.');
  }

  // ── Capabilities ─────────────────────────────────────────────────────

  /// Returns the platform capabilities for Bluetooth Classic.
  Future<BtcPlatformCapabilities> getPlatformCapabilities() {
    throw UnimplementedError(
        'getPlatformCapabilities() has not been implemented.');
  }
}
