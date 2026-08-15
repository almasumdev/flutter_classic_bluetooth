import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MethodChannelFlutterClassicBluetooth', () {
    late MethodChannelFlutterClassicBluetooth platform;
    late List<MethodCall> log;

    setUp(() {
      platform = MethodChannelFlutterClassicBluetooth();
      log = [];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        platform.methodChannel,
        (MethodCall call) async {
          log.add(call);
          switch (call.method) {
            case 'isSupported':
              return true;
            case 'isEnabled':
              return true;
            case 'enableBluetooth':
              return true;
            case 'disableBluetooth':
              return true;
            case 'getAdapterName':
              return 'MockAdapter';
            case 'getAdapterAddress':
              return '11:22:33:44:55:66';
            case 'startDiscovery':
              return null;
            case 'stopDiscovery':
              return null;
            case 'isDiscovering':
              return false;
            case 'getPairedDevices':
              return [
                {
                  'address': 'AA:BB:CC:DD:EE:FF',
                  'name': 'Device1',
                  'bondState': 'bonded',
                }
              ];
            case 'bondDevice':
              return true;
            case 'unbondDevice':
              return true;
            case 'connect':
              return {'id': 1, 'address': call.arguments['address']};
            case 'disconnect':
              return null;
            case 'write':
              return null;
            case 'startServer':
              return {'id': 1};
            case 'stopServer':
              return null;
            case 'setDiscoverable':
              return true;
            case 'getPlatformCapabilities':
              return {
                'canEnableBluetooth': true,
                'canDisableBluetooth': false,
                'canDiscoverDevices': true,
                'canGetPairedDevices': true,
                'canBondDevices': true,
                'canUnbondDevices': true,
                'canCreateServer': true,
                'canSetDiscoverable': false,
                'supportsMultipleConnections': true,
                'supportsSecureConnection': true,
                'supportsInsecureConnection': false,
                'requiresMfiCertification': false,
                'platformNote': 'Test platform',
              };
            default:
              return null;
          }
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform.methodChannel, null);
    });

    test('isSupported sends correct method', () async {
      final result = await platform.isSupported();
      expect(result, isTrue);
      expect(log.last.method, 'isSupported');
    });

    test('isEnabled sends correct method', () async {
      final result = await platform.isEnabled();
      expect(result, isTrue);
      expect(log.last.method, 'isEnabled');
    });

    test('enableBluetooth sends correct method', () async {
      final result = await platform.enableBluetooth();
      expect(result, isTrue);
      expect(log.last.method, 'enableBluetooth');
    });

    test('disableBluetooth sends correct method', () async {
      final result = await platform.disableBluetooth();
      expect(result, isTrue);
      expect(log.last.method, 'disableBluetooth');
    });

    test('getAdapterName sends correct method', () async {
      final result = await platform.getAdapterName();
      expect(result, 'MockAdapter');
      expect(log.last.method, 'getAdapterName');
    });

    test('getAdapterAddress sends correct method', () async {
      final result = await platform.getAdapterAddress();
      expect(result, '11:22:33:44:55:66');
      expect(log.last.method, 'getAdapterAddress');
    });

    test('startDiscovery sends correct method', () async {
      await platform.startDiscovery();
      expect(log.last.method, 'startDiscovery');
    });

    test('stopDiscovery sends correct method', () async {
      await platform.stopDiscovery();
      expect(log.last.method, 'stopDiscovery');
    });

    test('isDiscovering sends correct method', () async {
      final result = await platform.isDiscovering();
      expect(result, isFalse);
      expect(log.last.method, 'isDiscovering');
    });

    test('getPairedDevices sends correct method and parses result', () async {
      final devices = await platform.getPairedDevices();
      expect(log.last.method, 'getPairedDevices');
      expect(devices, hasLength(1));
      expect(devices.first.address, 'AA:BB:CC:DD:EE:FF');
      expect(devices.first.name, 'Device1');
      expect(devices.first.bondState, BtcBondState.bonded);
    });

    test('bondDevice sends address argument', () async {
      final result = await platform.bondDevice('11:22:33:44:55:66');
      expect(result, isTrue);
      expect(log.last.method, 'bondDevice');
      expect(log.last.arguments, {'address': '11:22:33:44:55:66'});
    });

    test('unbondDevice sends address argument', () async {
      final result = await platform.unbondDevice('11:22:33:44:55:66');
      expect(result, isTrue);
      expect(log.last.method, 'unbondDevice');
      expect(log.last.arguments, {'address': '11:22:33:44:55:66'});
    });

    test('connect sends correct arguments and returns connection', () async {
      final connection = await platform.connect(
        address: 'AA:BB:CC:DD:EE:FF',
        uuid: '00001101-0000-1000-8000-00805F9B34FB',
        secure: true,
      );
      expect(log.last.method, 'connect');
      expect(log.last.arguments, {
        'address': 'AA:BB:CC:DD:EE:FF',
        'uuid': '00001101-0000-1000-8000-00805F9B34FB',
        'secure': true,
      });
      expect(connection.id, 1);
      expect(connection.address, 'AA:BB:CC:DD:EE:FF');
    });

    test('connect defaults uuid to SPP when omitted', () async {
      await platform.connect(address: 'AA:BB:CC:DD:EE:FF');
      expect(log.last.method, 'connect');
      expect(log.last.arguments['uuid'], BtcUuid.spp);
      expect(log.last.arguments['secure'], true);
    });

    test('startServer defaults uuid to SPP when omitted', () async {
      await platform.startServer(serviceName: 'TestService');
      expect(log.last.method, 'startServer');
      expect(log.last.arguments['uuid'], BtcUuid.spp);
      expect(log.last.arguments['serviceName'], 'TestService');
    });

    test('disconnect sends id argument', () async {
      await platform.disconnect(5);
      expect(log.last.method, 'disconnect');
      expect(log.last.arguments, {'id': 5});
    });

    test('write sends id and data arguments', () async {
      final data = Uint8List.fromList([1, 2, 3]);
      await platform.write(5, data);
      expect(log.last.method, 'write');
      expect(log.last.arguments['id'], 5);
      expect(log.last.arguments['data'], data);
    });

    test('startServer sends correct arguments and returns server', () async {
      final server = await platform.startServer(
        uuid: '00001101-0000-1000-8000-00805F9B34FB',
        serviceName: 'TestService',
        secure: true,
      );
      expect(log.last.method, 'startServer');
      expect(log.last.arguments, {
        'uuid': '00001101-0000-1000-8000-00805F9B34FB',
        'serviceName': 'TestService',
        'secure': true,
      });
      expect(server.id, 1);
      expect(server.uuid, '00001101-0000-1000-8000-00805F9B34FB');
      expect(server.serviceName, 'TestService');
    });

    test('stopServer sends id argument', () async {
      await platform.stopServer(3);
      expect(log.last.method, 'stopServer');
      expect(log.last.arguments, {'id': 3});
    });

    test('setDiscoverable sends duration argument', () async {
      final result = await platform.setDiscoverable(300);
      expect(result, isTrue);
      expect(log.last.method, 'setDiscoverable');
      expect(log.last.arguments, {'duration': 300});
    });

    test('getPlatformCapabilities parses all fields', () async {
      final caps = await platform.getPlatformCapabilities();
      expect(log.last.method, 'getPlatformCapabilities');
      expect(caps.canEnableBluetooth, isTrue);
      expect(caps.canDisableBluetooth, isFalse);
      expect(caps.canDiscoverDevices, isTrue);
      expect(caps.canGetPairedDevices, isTrue);
      expect(caps.canBondDevices, isTrue);
      expect(caps.canUnbondDevices, isTrue);
      expect(caps.canCreateServer, isTrue);
      expect(caps.canSetDiscoverable, isFalse);
      expect(caps.supportsMultipleConnections, isTrue);
      expect(caps.supportsSecureConnection, isTrue);
      expect(caps.supportsInsecureConnection, isFalse);
      expect(caps.requiresMfiCertification, isFalse);
      expect(caps.platformNote, 'Test platform');
    });

    test('PlatformException converted to BtcUnsupportedException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform.methodChannel, (call) async {
        throw PlatformException(
          code: 'unsupported',
          message: 'Feature not available',
          details: {'feature': 'discovery', 'platform': 'iOS'},
        );
      });

      expect(
        () => platform.isSupported(),
        throwsA(isA<BtcUnsupportedException>().having(
          (e) => e.feature,
          'feature',
          'discovery',
        )),
      );
    });

    test('PlatformException converted to BtcPermissionException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform.methodChannel, (call) async {
        throw PlatformException(
            code: 'permissionDenied', message: 'No BT permission');
      });

      expect(
        () => platform.isEnabled(),
        throwsA(isA<BtcPermissionException>()),
      );
    });

    test('PlatformException converted to BtcDisabledException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform.methodChannel, (call) async {
        throw PlatformException(code: 'bluetoothDisabled', message: 'BT off');
      });

      expect(
        () => platform.startDiscovery(),
        throwsA(isA<BtcDisabledException>()),
      );
    });

    test('PlatformException converted to BtcConnectionException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform.methodChannel, (call) async {
        throw PlatformException(
          code: 'connectionFailed',
          message: 'Refused',
          details: {'address': 'AA:BB:CC:DD:EE:FF'},
        );
      });

      expect(
        () => platform.connect(
          address: 'AA:BB:CC:DD:EE:FF',
          uuid: '00001101-0000-1000-8000-00805F9B34FB',
        ),
        throwsA(isA<BtcConnectionException>().having(
          (e) => e.address,
          'address',
          'AA:BB:CC:DD:EE:FF',
        )),
      );
    });

    test('PlatformException converted to BtcWriteException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform.methodChannel, (call) async {
        throw PlatformException(code: 'writeFailed', message: 'Write error');
      });

      expect(
        () => platform.write(1, Uint8List(0)),
        throwsA(isA<BtcWriteException>()),
      );
    });

    test('PlatformException converted to BtcTimeoutException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform.methodChannel, (call) async {
        throw PlatformException(
          code: 'timeout',
          message: 'Timed out',
          details: {'timeoutMs': 5000},
        );
      });

      expect(
        () => platform.connect(
          address: 'AA:BB:CC:DD:EE:FF',
          uuid: '00001101-0000-1000-8000-00805F9B34FB',
        ),
        throwsA(isA<BtcTimeoutException>().having(
          (e) => e.timeoutMs,
          'timeoutMs',
          5000,
        )),
      );
    });

    test('Unknown PlatformException converted to BtcException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform.methodChannel, (call) async {
        throw PlatformException(code: 'unknown_code', message: 'Something');
      });

      expect(
        () => platform.isSupported(),
        throwsA(isA<BtcException>().having(
          (e) => e.code,
          'code',
          'unknown_code',
        )),
      );
    });
  });

  // ── BtcDevice Model ──────────────────────────────────────────────────
}
