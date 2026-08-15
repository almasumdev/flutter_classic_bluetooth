import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';

import 'mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Platform interface', () {
    test('MethodChannelFlutterClassicBluetooth is the default instance', () {
      expect(
        FlutterClassicBluetoothPlatform.instance,
        isA<MethodChannelFlutterClassicBluetooth>(),
      );
    });

    test('platform interface throws UnimplementedError for all methods', () {
      final platform = _UnimplementedPlatform();

      expect(() => platform.isSupported(), throwsUnimplementedError);
      expect(() => platform.isEnabled(), throwsUnimplementedError);
      expect(() => platform.enableBluetooth(), throwsUnimplementedError);
      expect(() => platform.disableBluetooth(), throwsUnimplementedError);
      expect(() => platform.adapterState(), throwsUnimplementedError);
      expect(() => platform.getAdapterName(), throwsUnimplementedError);
      expect(() => platform.getAdapterAddress(), throwsUnimplementedError);
      expect(() => platform.startDiscovery(), throwsUnimplementedError);
      expect(() => platform.stopDiscovery(), throwsUnimplementedError);
      expect(() => platform.isDiscovering(), throwsUnimplementedError);
      expect(() => platform.discoveryState(), throwsUnimplementedError);
      expect(() => platform.discoveryResults(), throwsUnimplementedError);
      expect(() => platform.getPairedDevices(), throwsUnimplementedError);
      expect(() => platform.bondDevice('AA:BB:CC:DD:EE:FF'),
          throwsUnimplementedError);
      expect(() => platform.unbondDevice('AA:BB:CC:DD:EE:FF'),
          throwsUnimplementedError);
      expect(() => platform.bondState('AA:BB:CC:DD:EE:FF'),
          throwsUnimplementedError);
      expect(
        () => platform.connect(
          address: 'AA:BB:CC:DD:EE:FF',
          uuid: '00001101-0000-1000-8000-00805F9B34FB',
        ),
        throwsUnimplementedError,
      );
      expect(() => platform.disconnect(0), throwsUnimplementedError);
      expect(() => platform.write(0, Uint8List(0)), throwsUnimplementedError);
      expect(
        () => platform.startServer(
          uuid: '00001101-0000-1000-8000-00805F9B34FB',
          serviceName: 'test',
        ),
        throwsUnimplementedError,
      );
      expect(() => platform.stopServer(0), throwsUnimplementedError);
      expect(() => platform.setDiscoverable(120), throwsUnimplementedError);
      expect(
          () => platform.getPlatformCapabilities(), throwsUnimplementedError);
    });

    test('can set platform instance', () {
      final mock = MockFlutterClassicBluetoothPlatform();
      FlutterClassicBluetoothPlatform.instance = mock;
      expect(FlutterClassicBluetoothPlatform.instance, same(mock));
    });
  });

  // ── FlutterClassicBluetooth (Main Plugin Class) ──────────────────────

  group('FlutterClassicBluetooth', () {
    late FlutterClassicBluetooth bluetooth;
    late MockFlutterClassicBluetoothPlatform mockPlatform;

    setUp(() {
      mockPlatform = MockFlutterClassicBluetoothPlatform();
      FlutterClassicBluetoothPlatform.instance = mockPlatform;
      bluetooth = FlutterClassicBluetooth();
    });

    test('singleton returns same instance', () {
      final a = FlutterClassicBluetooth();
      final b = FlutterClassicBluetooth();
      expect(identical(a, b), isTrue);
    });

    test('isSupported returns true from mock', () async {
      expect(await bluetooth.isSupported(), isTrue);
    });

    test('isEnabled returns true from mock', () async {
      expect(await bluetooth.isEnabled(), isTrue);
    });

    test('enableBluetooth returns true from mock', () async {
      expect(await bluetooth.enableBluetooth(), isTrue);
    });

    test('disableBluetooth returns true from mock', () async {
      expect(await bluetooth.disableBluetooth(), isTrue);
    });

    test('getAdapterName returns test name', () async {
      expect(await bluetooth.getAdapterName(), 'TestAdapter');
    });

    test('getAdapterAddress returns test address', () async {
      expect(await bluetooth.getAdapterAddress(), 'AA:BB:CC:DD:EE:FF');
    });

    test('startDiscovery completes without error', () async {
      await bluetooth.startDiscovery();
    });

    test('stopDiscovery completes without error', () async {
      await bluetooth.stopDiscovery();
    });

    test('isDiscovering returns false from mock', () async {
      expect(await bluetooth.isDiscovering(), isFalse);
    });

    test('getPairedDevices returns mock list', () async {
      final devices = await bluetooth.getPairedDevices();
      expect(devices, hasLength(1));
      expect(devices.first.address, 'AA:BB:CC:DD:EE:FF');
      expect(devices.first.name, 'TestDevice');
    });

    test('bondDevice returns true for valid address', () async {
      expect(await bluetooth.bondDevice('AA:BB:CC:DD:EE:FF'), isTrue);
    });

    test('unbondDevice returns true for valid address', () async {
      expect(await bluetooth.unbondDevice('AA:BB:CC:DD:EE:FF'), isTrue);
    });

    test('setDiscoverable returns true', () async {
      expect(await bluetooth.setDiscoverable(120), isTrue);
    });

    test('getPlatformCapabilities returns mock capabilities', () async {
      final caps = await bluetooth.getPlatformCapabilities();
      expect(caps.canDiscoverDevices, isTrue);
      expect(caps.canGetPairedDevices, isTrue);
      expect(caps.canBondDevices, isTrue);
      expect(caps.supportsMultipleConnections, isTrue);
    });

    test('adapterState stream emits values', () async {
      final state = await bluetooth.adapterState.first;
      expect(state, BtcAdapterState.on);
    });

    test('discoveryState stream emits values', () async {
      final state = await bluetooth.discoveryState.first;
      expect(state, isFalse);
    });
  });

  // ── Input Validation ──────────────────────────────────────────────────

  group('Input validation', () {
    late FlutterClassicBluetooth bluetooth;

    setUp(() {
      FlutterClassicBluetoothPlatform.instance =
          MockFlutterClassicBluetoothPlatform();
      bluetooth = FlutterClassicBluetooth();
    });

    test('bondDevice throws on invalid address', () {
      expect(
        () => bluetooth.bondDevice('invalid'),
        throwsA(isA<BtcAddressException>()),
      );
    });

    test('bondDevice throws on empty address', () {
      expect(
        () => bluetooth.bondDevice(''),
        throwsA(isA<BtcAddressException>()),
      );
    });

    test('unbondDevice throws on invalid address', () {
      expect(
        () => bluetooth.unbondDevice('ZZZZ'),
        throwsA(isA<BtcAddressException>()),
      );
    });

    test('connect throws on invalid address', () {
      expect(
        () => bluetooth.connect(
          address: 'bad-address',
          uuid: '00001101-0000-1000-8000-00805F9B34FB',
        ),
        throwsA(isA<BtcAddressException>()),
      );
    });

    test('connect throws on invalid UUID', () {
      expect(
        () => bluetooth.connect(
          address: 'AA:BB:CC:DD:EE:FF',
          uuid: 'not-a-uuid',
        ),
        throwsA(isA<BtcUuidException>()),
      );
    });

    test('connect throws on short UUID', () {
      expect(
        () => bluetooth.connect(
          address: 'AA:BB:CC:DD:EE:FF',
          uuid: '0000-1101',
        ),
        throwsA(isA<BtcUuidException>()),
      );
    });

    test('startServer throws on invalid UUID', () {
      expect(
        () => bluetooth.startServer(uuid: 'bad', serviceName: 'test'),
        throwsA(isA<BtcUuidException>()),
      );
    });

    test('bondDevice accepts valid MAC address', () async {
      final result = await bluetooth.bondDevice('AA:BB:CC:DD:EE:FF');
      expect(result, isTrue);
    });

    test('bondDevice accepts lowercase MAC', () async {
      final result = await bluetooth.bondDevice('aa:bb:cc:dd:ee:ff');
      expect(result, isTrue);
    });

    test('connect accepts valid address and UUID', () {
      // The mock throws UnimplementedError for connect, which is fine.
      // We verify validation passes.
      expect(
        () => bluetooth.connect(
          address: 'AA:BB:CC:DD:EE:FF',
          uuid: '00001101-0000-1000-8000-00805F9B34FB',
        ),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('connect with no uuid passes validation (defaults to SPP)', () {
      // Validation passes (no BtcUuidException) and reaches the mock,
      // which throws UnimplementedError, proving the SPP default is valid.
      expect(
        () => bluetooth.connect(address: 'AA:BB:CC:DD:EE:FF'),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('startServer with no uuid passes validation (defaults to SPP)', () {
      expect(
        () => bluetooth.startServer(serviceName: 'svc'),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('bondState throws on invalid address', () {
      expect(
        () => bluetooth.bondState('not-valid'),
        throwsA(isA<BtcAddressException>()),
      );
    });

    test('bondState returns stream for valid address', () async {
      final state = await bluetooth.bondState('AA:BB:CC:DD:EE:FF').first;
      expect(state, BtcBondState.bonded);
    });
  });

  // ── Method Channel Tests ──────────────────────────────────────────────

  group('scan', () {
    test('collects, de-dupes and sorts results by signal', () async {
      final platform = _ScanPlatform();
      FlutterClassicBluetoothPlatform.instance = platform;
      addTearDown(platform.controller.close);
      final bluetooth = FlutterClassicBluetooth();

      final devices =
          await bluetooth.scan(timeout: const Duration(milliseconds: 60));

      expect(
        devices.map((d) => d.address).toList(),
        ['AA:BB:CC:DD:EE:F1', 'AA:BB:CC:DD:EE:F2'], // strongest first
      );
      expect(
          devices.first.name, 'One'); // preserved across the rssi-only update
      expect(devices.first.rssi, -35); // updated
    });
  });

  // ── Frame splitting / line reading ────────────────────────────────────

  // ── Connect timeout ────────────────────────────────────────

  group('connect timeout', () {
    const method = MethodChannel('flutter_classic_bluetooth/methods');

    BtcConnection buildConnection(int id, List<MethodCall> calls) {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(method, (call) async {
        calls.add(call);
        return null;
      });
      for (final name in [
        'flutter_classic_bluetooth/connection/$id',
        'flutter_classic_bluetooth/connection_state/$id',
      ]) {
        messenger.setMockStreamHandler(
          EventChannel(name),
          MockStreamHandler.inline(onListen: (args, sink) {}),
        );
      }
      return BtcConnection(
        id: id,
        address: 'AA:BB:CC:DD:EE:FF',
        methodChannel: method,
      );
    }

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(method, null);
    });

    test('throws BtcTimeoutException when the deadline passes first', () async {
      final calls = <MethodCall>[];
      final connection = buildConnection(11, calls);
      FlutterClassicBluetoothPlatform.instance = _LateConnectPlatform(
        const Duration(milliseconds: 80),
        connection,
      );

      await expectLater(
        FlutterClassicBluetooth().connect(
          address: 'AA:BB:CC:DD:EE:FF',
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(isA<BtcTimeoutException>()
            .having((e) => e.timeoutMs, 'timeoutMs', 10)),
      );

      // Let the late attempt land and clean up inside this test.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(calls.where((c) => c.method == 'disconnect'), hasLength(1));
    });

    test('releases a connection that lands after the deadline', () async {
      final calls = <MethodCall>[];
      final connection = buildConnection(12, calls);
      FlutterClassicBluetoothPlatform.instance = _LateConnectPlatform(
        const Duration(milliseconds: 40),
        connection,
      );

      await expectLater(
        FlutterClassicBluetooth().connect(
          address: 'AA:BB:CC:DD:EE:FF',
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(isA<BtcTimeoutException>()),
      );

      // The native attempt is still running; give it time to land.
      await Future<void>.delayed(const Duration(milliseconds: 120));

      final disconnects = calls.where(
        (c) => c.method == 'disconnect' && c.arguments['id'] == 12,
      );
      expect(disconnects, hasLength(1));
      expect(connection.output.isClosed, isTrue);
    });

    test('keeps the connection when it beats the deadline', () async {
      final calls = <MethodCall>[];
      final connection = buildConnection(13, calls);
      FlutterClassicBluetoothPlatform.instance = _LateConnectPlatform(
        const Duration(milliseconds: 5),
        connection,
      );

      final result = await FlutterClassicBluetooth().connect(
        address: 'AA:BB:CC:DD:EE:FF',
        timeout: const Duration(milliseconds: 200),
      );

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(result.id, 13);
      expect(calls.where((c) => c.method == 'disconnect'), isEmpty);
      expect(connection.output.isClosed, isFalse);
    });
  });
}

class _UnimplementedPlatform extends FlutterClassicBluetoothPlatform {}

class _ScanPlatform extends MockFlutterClassicBluetoothPlatform {
  final StreamController<BtcDevice> controller =
      StreamController<BtcDevice>.broadcast();

  @override
  Stream<BtcDevice> discoveryResults() => controller.stream;

  @override
  Future<void> startDiscovery() async {
    controller.add(
      const BtcDevice(address: 'AA:BB:CC:DD:EE:F1', name: 'One', rssi: -40),
    );
    controller.add(
      const BtcDevice(address: 'AA:BB:CC:DD:EE:F2', name: 'Two', rssi: -70),
    );
    // A follow-up sighting of F1 with only a stronger RSSI (no name).
    controller.add(const BtcDevice(address: 'AA:BB:CC:DD:EE:F1', rssi: -35));
  }
}

class _LateConnectPlatform extends MockFlutterClassicBluetoothPlatform {
  _LateConnectPlatform(this.delay, this.connection);

  final Duration delay;
  final BtcConnection connection;

  @override
  Future<BtcConnection> connect({
    required String address,
    String uuid = BtcUuid.spp,
    bool secure = true,
  }) =>
      Future.delayed(delay, () => connection);
}
