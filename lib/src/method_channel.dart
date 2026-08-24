import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'btc_uuid.dart';
import 'platform_interface.dart';
import 'models/btc_enums.dart';
import 'models/btc_connection.dart';
import 'models/btc_device.dart';
import 'models/btc_server_socket.dart';
import 'models/btc_platform_capabilities.dart';
import 'models/btc_exceptions.dart';

/// An implementation of [FlutterClassicBluetoothPlatform] that uses
/// method channels and event channels to communicate with native code.
///
/// {@category Platform}
class MethodChannelFlutterClassicBluetooth
    extends FlutterClassicBluetoothPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel =
      const MethodChannel('flutter_classic_bluetooth/methods');

  // Event channels
  final _adapterStateChannel =
      const EventChannel('flutter_classic_bluetooth/adapter_state');
  final _discoveryStateChannel =
      const EventChannel('flutter_classic_bluetooth/discovery_state');
  final _discoveryResultsChannel =
      const EventChannel('flutter_classic_bluetooth/discovery_results');
  final _bondStateChannel =
      const EventChannel('flutter_classic_bluetooth/bond_state');

  // Cached broadcast streams
  Stream<BtcAdapterState>? _adapterStateStream;
  Stream<bool>? _discoveryStateStream;
  Stream<BtcDevice>? _discoveryResultsStream;

  // ── Permissions ──────────────────────────────────────────────────────

  @override
  Future<BtcPermissionStatus> checkPermissions(
      Set<BtcPermission> permissions) async {
    return _permissionStatus(
      await _invokeOptional<String>('checkPermissions', permissions),
    );
  }

  @override
  Future<BtcPermissionStatus> requestPermissions(
      Set<BtcPermission> permissions) async {
    return _permissionStatus(
      await _invokeOptional<String>('requestPermissions', permissions),
    );
  }

  @override
  Future<bool> openAppSettings() async {
    return await _invokeOptional<bool>('openAppSettings') ?? false;
  }

  @override
  Future<bool> isLocationServiceRequired() async {
    return await _invokeOptional<bool>('isLocationServiceRequired') ?? false;
  }

  @override
  Future<bool> isLocationServiceEnabled() async {
    return await _invokeOptional<bool>('isLocationServiceEnabled') ?? true;
  }

  @override
  Future<bool> openLocationSettings() async {
    return await _invokeOptional<bool>('openLocationSettings') ?? false;
  }

  /// Like `_invoke`, but returns `null` when the native side does not
  /// implement the method.
  ///
  /// The permission methods arrived after the rest of the channel contract, so
  /// a Dart layer newer than the bundled native build would otherwise throw
  /// [MissingPluginException] here. A platform with no permission API has
  /// nothing to report, which is what `null` means to the callers below.
  Future<T?> _invokeOptional<T>(
    String method, [
    Set<BtcPermission>? permissions,
  ]) async {
    try {
      return await _invoke<T>(
        method,
        permissions == null
            ? null
            : {'permissions': permissions.map((p) => p.name).toList()},
      );
    } on MissingPluginException {
      return null;
    }
  }

  /// Maps a native status name onto [BtcPermissionStatus].
  ///
  /// A platform that predates this method returns nothing, which reads as
  /// [BtcPermissionStatus.notRequired]: it has no runtime permission model, so
  /// there is nothing for the caller to request.
  BtcPermissionStatus _permissionStatus(String? name) {
    return BtcPermissionStatus.values.firstWhere(
      (e) => e.name == name,
      orElse: () => BtcPermissionStatus.notRequired,
    );
  }

  // ── Adapter ──────────────────────────────────────────────────────────

  @override
  Future<bool> isSupported() async {
    return await _invoke<bool>('isSupported') ?? false;
  }

  @override
  Future<bool> isEnabled() async {
    return await _invoke<bool>('isEnabled') ?? false;
  }

  @override
  Future<bool> enableBluetooth() async {
    return await _invoke<bool>('enableBluetooth') ?? false;
  }

  @override
  Future<bool> disableBluetooth() async {
    return await _invoke<bool>('disableBluetooth') ?? false;
  }

  @override
  Stream<BtcAdapterState> adapterState() {
    _adapterStateStream ??= _adapterStateChannel
        .receiveBroadcastStream()
        .map((event) => BtcAdapterState.values.firstWhere(
              (e) => e.name == event,
              orElse: () => BtcAdapterState.unknown,
            ));
    return _adapterStateStream!;
  }

  @override
  Future<String?> getAdapterName() {
    return _invoke<String>('getAdapterName');
  }

  @override
  Future<String?> getAdapterAddress() {
    return _invoke<String>('getAdapterAddress');
  }

  // ── Discovery ────────────────────────────────────────────────────────

  @override
  Future<void> startDiscovery() async {
    await _invoke<void>('startDiscovery');
  }

  @override
  Future<void> stopDiscovery() async {
    await _invoke<void>('stopDiscovery');
  }

  @override
  Future<bool> isDiscovering() async {
    return await _invoke<bool>('isDiscovering') ?? false;
  }

  @override
  Stream<bool> discoveryState() {
    _discoveryStateStream ??= _discoveryStateChannel
        .receiveBroadcastStream()
        .map((event) => event as bool);
    return _discoveryStateStream!;
  }

  @override
  Stream<BtcDevice> discoveryResults() {
    _discoveryResultsStream ??= _discoveryResultsChannel
        .receiveBroadcastStream()
        .map((event) => BtcDevice.fromMap(
              Map<dynamic, dynamic>.from(event as Map),
            ));
    return _discoveryResultsStream!;
  }

  // ── Pairing ──────────────────────────────────────────────────────────

  @override
  Future<List<BtcDevice>> getPairedDevices() async {
    final result = await _invoke<List>('getPairedDevices');
    if (result == null) return [];
    return result
        .map((e) => BtcDevice.fromMap(Map<dynamic, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<bool> bondDevice(String address) async {
    return await _invoke<bool>('bondDevice', {'address': address}) ?? false;
  }

  @override
  Future<bool> unbondDevice(String address) async {
    return await _invoke<bool>('unbondDevice', {'address': address}) ?? false;
  }

  @override
  Stream<BtcBondState> bondState(String address) {
    return _bondStateChannel
        .receiveBroadcastStream({'address': address}).map((event) {
      return BtcBondState.values.firstWhere(
        (e) => e.name == event,
        orElse: () => BtcBondState.none,
      );
    });
  }

  // ── Connection ───────────────────────────────────────────────────────

  @override
  Future<BtcConnection> connect({
    required String address,
    String uuid = BtcUuid.spp,
    bool secure = true,
  }) async {
    final result = await _invoke<Map>('connect', {
      'address': address,
      'uuid': uuid,
      'secure': secure,
    });
    final map = Map<dynamic, dynamic>.from(result!);
    return BtcConnection(
      id: map['id'] as int,
      address: address,
      methodChannel: methodChannel,
    );
  }

  @override
  Future<void> disconnect(int id) async {
    await _invoke<void>('disconnect', {'id': id});
  }

  @override
  Future<void> write(int id, Uint8List data) async {
    await _invoke<void>('write', {'id': id, 'data': data});
  }

  // ── Server ───────────────────────────────────────────────────────────

  @override
  Future<BtcServerSocket> startServer({
    required String serviceName,
    String uuid = BtcUuid.spp,
    bool secure = true,
  }) async {
    final result = await _invoke<Map>('startServer', {
      'uuid': uuid,
      'serviceName': serviceName,
      'secure': secure,
    });
    final map = Map<dynamic, dynamic>.from(result!);
    return BtcServerSocket(
      id: map['id'] as int,
      uuid: uuid,
      serviceName: serviceName,
      methodChannel: methodChannel,
    );
  }

  @override
  Future<void> stopServer(int id) async {
    await _invoke<void>('stopServer', {'id': id});
  }

  // ── Discoverability ──────────────────────────────────────────────────

  @override
  Future<bool> setDiscoverable(int durationSeconds) async {
    return await _invoke<bool>(
            'setDiscoverable', {'duration': durationSeconds}) ??
        false;
  }

  // ── Capabilities ─────────────────────────────────────────────────────

  @override
  Future<BtcPlatformCapabilities> getPlatformCapabilities() async {
    final result = await _invoke<Map>('getPlatformCapabilities');
    return BtcPlatformCapabilities.fromMap(
      Map<dynamic, dynamic>.from(result!),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  /// Invokes a method on the platform channel and converts
  /// [PlatformException] to typed [BtcException].
  Future<T?> _invoke<T>(String method,
      [Map<String, dynamic>? arguments]) async {
    try {
      return await methodChannel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      throw _convertException(e);
    }
  }

  /// Converts a [PlatformException] to a typed [BtcException].
  BtcException _convertException(PlatformException e) {
    switch (e.code) {
      case 'unsupported':
        return BtcUnsupportedException(
          feature: e.details?['feature'] as String? ?? 'unknown',
          platform: e.details?['platform'] as String? ?? 'unknown',
          reason: e.message,
        );
      case 'permissionDenied':
        return BtcPermissionException(e.message ?? 'Permission denied');
      case 'bluetoothDisabled':
        return BtcDisabledException(
            e.message ?? 'Bluetooth adapter is disabled');
      case 'connectionFailed':
        return BtcConnectionException(
          e.message ?? 'Connection failed',
          address: e.details?['address'] as String?,
        );
      case 'writeFailed':
        return BtcWriteException(e.message ?? 'Write failed');
      case 'discoveryFailed':
        return BtcDiscoveryException(e.message ?? 'Failed to start discovery');
      case 'timeout':
        return BtcTimeoutException(
          message: e.message ?? 'Operation timed out',
          timeoutMs: e.details?['timeoutMs'] as int?,
        );
      case 'invalidAddress':
        return BtcAddressException(
            e.details?['address'] as String? ?? 'unknown');
      case 'invalidUuid':
        return BtcUuidException(e.details?['uuid'] as String? ?? 'unknown');
      default:
        return BtcException(
          e.message ?? 'Unknown Bluetooth error',
          code: e.code,
        );
    }
  }
}
