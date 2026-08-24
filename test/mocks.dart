import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Fake platform implementation shared by the test suite.
class MockFlutterClassicBluetoothPlatform
    with MockPlatformInterfaceMixin
    implements FlutterClassicBluetoothPlatform {
  /// Overridden by tests that exercise the permission flow.
  BtcPermissionStatus permissionStatus = BtcPermissionStatus.granted;

  /// Records each permission call, in order.
  final permissionCalls = <String>[];

  @override
  Future<BtcPermissionStatus> checkPermissions() {
    permissionCalls.add('check');
    return Future.value(permissionStatus);
  }

  @override
  Future<BtcPermissionStatus> requestPermissions() {
    permissionCalls.add('request');
    return Future.value(permissionStatus);
  }

  @override
  Future<bool> openAppSettings() {
    permissionCalls.add('settings');
    return Future.value(true);
  }

  @override
  Future<bool> isSupported() => Future.value(true);

  @override
  Future<bool> isEnabled() => Future.value(true);

  @override
  Future<bool> enableBluetooth() => Future.value(true);

  @override
  Future<bool> disableBluetooth() => Future.value(true);

  @override
  Stream<BtcAdapterState> adapterState() => Stream.value(BtcAdapterState.on);

  @override
  Future<String?> getAdapterName() => Future.value('TestAdapter');

  @override
  Future<String?> getAdapterAddress() => Future.value('AA:BB:CC:DD:EE:FF');

  @override
  Future<void> startDiscovery() => Future.value();

  @override
  Future<void> stopDiscovery() => Future.value();

  @override
  Future<bool> isDiscovering() => Future.value(false);

  @override
  Stream<bool> discoveryState() => Stream.value(false);

  @override
  Stream<BtcDevice> discoveryResults() => const Stream.empty();

  @override
  Future<List<BtcDevice>> getPairedDevices() => Future.value([
        const BtcDevice(
          address: 'AA:BB:CC:DD:EE:FF',
          name: 'TestDevice',
          bondState: BtcBondState.bonded,
        ),
      ]);

  @override
  Future<bool> bondDevice(String address) => Future.value(true);

  @override
  Future<bool> unbondDevice(String address) => Future.value(true);

  @override
  Stream<BtcBondState> bondState(String address) =>
      Stream.value(BtcBondState.bonded);

  @override
  Future<BtcConnection> connect({
    required String address,
    String uuid = BtcUuid.spp,
    bool secure = true,
  }) {
    throw UnimplementedError('connect() mock not implemented');
  }

  @override
  Future<void> disconnect(int id) => Future.value();

  @override
  Future<void> write(int id, Uint8List data) => Future.value();

  @override
  Future<BtcServerSocket> startServer({
    required String serviceName,
    String uuid = BtcUuid.spp,
    bool secure = true,
  }) {
    throw UnimplementedError('startServer() mock not implemented');
  }

  @override
  Future<void> stopServer(int id) => Future.value();

  @override
  Future<bool> setDiscoverable(int durationSeconds) => Future.value(true);

  @override
  Future<BtcPlatformCapabilities> getPlatformCapabilities() =>
      Future.value(const BtcPlatformCapabilities(
        canDiscoverDevices: true,
        canGetPairedDevices: true,
        canBondDevices: true,
        supportsMultipleConnections: true,
      ));
}
