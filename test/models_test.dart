import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BtcDevice', () {
    test('fromMap creates device correctly', () {
      final device = BtcDevice.fromMap({
        'address': '11:22:33:44:55:66',
        'name': 'TestDevice',
        'alias': 'MyDevice',
        'rssi': -50,
        'type': 'classic',
        'bondState': 'bonded',
        'uuids': ['00001101-0000-1000-8000-00805F9B34FB'],
      });

      expect(device.address, '11:22:33:44:55:66');
      expect(device.name, 'TestDevice');
      expect(device.alias, 'MyDevice');
      expect(device.rssi, -50);
      expect(device.type, BtcDeviceType.classic);
      expect(device.bondState, BtcBondState.bonded);
      expect(device.uuids, hasLength(1));
    });

    test('toMap round-trip is consistent', () {
      const original = BtcDevice(
        address: 'AA:BB:CC:DD:EE:FF',
        name: 'Dev',
        type: BtcDeviceType.dual,
        bondState: BtcBondState.bonding,
        uuids: ['uuid1'],
      );
      final map = original.toMap();
      final restored = BtcDevice.fromMap(map);

      expect(restored.address, original.address);
      expect(restored.name, original.name);
      expect(restored.type, original.type);
      expect(restored.bondState, original.bondState);
      expect(restored.uuids, original.uuids);
    });

    test('equality is based on address', () {
      const a = BtcDevice(address: 'AA:BB:CC:DD:EE:FF', name: 'A');
      const b = BtcDevice(address: 'AA:BB:CC:DD:EE:FF', name: 'B');
      const c = BtcDevice(address: '11:22:33:44:55:66', name: 'A');

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, b.hashCode);
    });

    test('displayName falls back through alias → name → address', () {
      const withAlias = BtcDevice(
        address: 'AA:BB:CC:DD:EE:FF',
        name: 'Name',
        alias: 'Alias',
      );
      const withName = BtcDevice(
        address: 'AA:BB:CC:DD:EE:FF',
        name: 'Name',
      );
      const addressOnly = BtcDevice(address: 'AA:BB:CC:DD:EE:FF');

      expect(withAlias.displayName, 'Alias');
      expect(withName.displayName, 'Name');
      expect(addressOnly.displayName, 'AA:BB:CC:DD:EE:FF');
    });

    test('fromMap handles missing optional fields', () {
      final device = BtcDevice.fromMap({
        'address': 'AA:BB:CC:DD:EE:FF',
      });
      expect(device.name, isNull);
      expect(device.alias, isNull);
      expect(device.rssi, isNull);
      expect(device.type, BtcDeviceType.unknown);
      expect(device.bondState, BtcBondState.none);
      expect(device.uuids, isEmpty);
    });

    test('fromMap handles unknown enum values', () {
      final device = BtcDevice.fromMap({
        'address': 'AA:BB:CC:DD:EE:FF',
        'type': 'nonexistent_type',
        'bondState': 'weird',
      });
      expect(device.type, BtcDeviceType.unknown);
      expect(device.bondState, BtcBondState.none);
    });

    test('toString contains address and name', () {
      const device = BtcDevice(address: 'AA:BB:CC:DD:EE:FF', name: 'Dev');
      expect(device.toString(), contains('AA:BB:CC:DD:EE:FF'));
      expect(device.toString(), contains('Dev'));
    });

    test('mergedWith keeps earlier non-null fields, applies new ones', () {
      const a = BtcDevice(
        address: 'AA:BB:CC:DD:EE:FF',
        name: 'Name',
        rssi: -50,
        uuids: ['u1'],
      );
      const b = BtcDevice(address: 'AA:BB:CC:DD:EE:FF', rssi: -40);
      final m = a.mergedWith(b);
      expect(m.name, 'Name'); // preserved (b had none)
      expect(m.rssi, -40); // updated
      expect(m.uuids, ['u1']); // preserved
    });
  });

  // ── PlatformCapabilities Model ────────────────────────────────────────

  group('PlatformCapabilities', () {
    test('fromMap creates capabilities correctly', () {
      final caps = BtcPlatformCapabilities.fromMap({
        'canDiscoverDevices': true,
        'canGetPairedDevices': true,
        'canBondDevices': true,
        'canUnbondDevices': true,
        'canCreateServer': true,
        'supportsMultipleConnections': true,
        'supportsSecureConnection': true,
        'supportsInsecureConnection': true,
        'platformNote': 'Test note',
      });

      expect(caps.canDiscoverDevices, isTrue);
      expect(caps.canGetPairedDevices, isTrue);
      expect(caps.canCreateServer, isTrue);
      expect(caps.supportsMultipleConnections, isTrue);
      expect(caps.platformNote, 'Test note');
      expect(caps.requiresMfiCertification, isFalse);
    });

    test('toMap round-trip is consistent', () {
      const original = BtcPlatformCapabilities(
        canDiscoverDevices: true,
        canEnableBluetooth: true,
        canReadConnectionRssi: true,
        requiresMfiCertification: true,
        platformNote: 'iOS',
      );
      final map = original.toMap();
      final restored = BtcPlatformCapabilities.fromMap(map);

      expect(restored.canDiscoverDevices, original.canDiscoverDevices);
      expect(restored.canEnableBluetooth, original.canEnableBluetooth);
      expect(restored.canReadConnectionRssi, original.canReadConnectionRssi);
      expect(
          restored.requiresMfiCertification, original.requiresMfiCertification);
      expect(restored.platformNote, original.platformNote);
    });

    test('defaults are all false/null', () {
      const caps = BtcPlatformCapabilities();
      expect(caps.canEnableBluetooth, isFalse);
      expect(caps.canDisableBluetooth, isFalse);
      expect(caps.canDiscoverDevices, isFalse);
      expect(caps.canGetPairedDevices, isFalse);
      expect(caps.canBondDevices, isFalse);
      expect(caps.canUnbondDevices, isFalse);
      expect(caps.canCreateServer, isFalse);
      expect(caps.canSetDiscoverable, isFalse);
      expect(caps.supportsMultipleConnections, isFalse);
      expect(caps.supportsSecureConnection, isFalse);
      expect(caps.supportsInsecureConnection, isFalse);
      expect(caps.canReadConnectionRssi, isFalse);
      expect(caps.requiresMfiCertification, isFalse);
      expect(caps.platformNote, isNull);
    });

    test('fromMap handles missing keys with defaults', () {
      final caps = BtcPlatformCapabilities.fromMap({});
      expect(caps.canEnableBluetooth, isFalse);
      expect(caps.canDiscoverDevices, isFalse);
      expect(caps.platformNote, isNull);
    });
  });

  // ── Exception Hierarchy ───────────────────────────────────────────────

  group('Exception hierarchy', () {
    test('BtcException stores message and code', () {
      const ex = BtcException('test error', code: 'testCode');
      expect(ex.message, 'test error');
      expect(ex.code, 'testCode');
      expect(ex.toString(), contains('testCode'));
    });

    test('BtcException without code', () {
      const ex = BtcException('simple error');
      expect(ex.code, isNull);
    });

    test('BtcUnsupportedException has feature and platform', () {
      const ex = BtcUnsupportedException(
        feature: 'discovery',
        platform: 'iOS',
      );
      expect(ex.feature, 'discovery');
      expect(ex.platform, 'iOS');
      expect(ex.toString(), contains('discovery'));
      expect(ex.toString(), contains('iOS'));
    });

    test('BtcUnsupportedException with custom reason', () {
      const ex = BtcUnsupportedException(
        feature: 'server',
        platform: 'iOS',
        reason: 'Custom reason',
      );
      expect(ex.message, 'Custom reason');
    });

    test('BtcConnectionException has address', () {
      const ex = BtcConnectionException(
        'Connection refused',
        address: 'AA:BB:CC:DD:EE:FF',
      );
      expect(ex.address, 'AA:BB:CC:DD:EE:FF');
      expect(ex.message, 'Connection refused');
      expect(ex.code, 'connectionFailed');
    });

    test('BtcConnectionException without address', () {
      const ex = BtcConnectionException('Failed');
      expect(ex.address, isNull);
    });

    test('BtcAddressException has address', () {
      const ex = BtcAddressException('INVALID');
      expect(ex.address, 'INVALID');
      expect(ex.toString(), contains('INVALID'));
      expect(ex.code, 'invalidAddress');
    });

    test('BtcUuidException has uuid', () {
      const ex = BtcUuidException('bad-uuid');
      expect(ex.uuid, 'bad-uuid');
      expect(ex.code, 'invalidUuid');
    });

    test('BtcTimeoutException has timeoutMs', () {
      const ex = BtcTimeoutException(timeoutMs: 3000);
      expect(ex.timeoutMs, 3000);
      expect(ex.code, 'timeout');
    });

    test('BtcPermissionException defaults', () {
      const ex = BtcPermissionException();
      expect(ex.message, 'Bluetooth permission denied');
      expect(ex.code, 'permissionDenied');
    });

    test('BtcDisabledException defaults', () {
      const ex = BtcDisabledException();
      expect(ex.message, 'Bluetooth adapter is disabled');
      expect(ex.code, 'bluetoothDisabled');
    });

    test('BtcWriteException defaults', () {
      const ex = BtcWriteException();
      expect(ex.message, 'Failed to write data');
      expect(ex.code, 'writeFailed');
    });

    test('all exceptions are BtcException', () {
      expect(
        const BtcPermissionException(),
        isA<BtcException>(),
      );
      expect(
        const BtcDisabledException(),
        isA<BtcException>(),
      );
      expect(
        const BtcWriteException(),
        isA<BtcException>(),
      );
      expect(
        const BtcTimeoutException(),
        isA<BtcException>(),
      );
      expect(
        const BtcAddressException('test'),
        isA<BtcException>(),
      );
      expect(
        const BtcUuidException('test'),
        isA<BtcException>(),
      );
      expect(
        const BtcUnsupportedException(feature: 'f', platform: 'p'),
        isA<BtcException>(),
      );
      expect(
        const BtcConnectionException('test'),
        isA<BtcException>(),
      );
    });

    test('all exceptions implement Exception', () {
      expect(const BtcException('test'), isA<Exception>());
      expect(const BtcPermissionException(), isA<Exception>());
    });
  });

  // ── BtcStreamSink ────────────────────────────────────────────────────

  group('Enums', () {
    test('BtcAdapterState has all expected values', () {
      expect(BtcAdapterState.values, hasLength(7));
      expect(BtcAdapterState.values, contains(BtcAdapterState.on));
      expect(BtcAdapterState.values, contains(BtcAdapterState.off));
      expect(BtcAdapterState.values, contains(BtcAdapterState.unknown));
    });

    test('BtcBondState has all expected values', () {
      expect(BtcBondState.values, hasLength(3));
    });

    test('BtcDeviceType has all expected values', () {
      expect(BtcDeviceType.values, hasLength(4));
    });

    test('BtcConnectionState has all expected values', () {
      expect(BtcConnectionState.values, hasLength(4));
    });
  });

  // ── BtcUuid Constants ─────────────────────────────────────────────────

  group('BtcUuid', () {
    test('spp is the canonical Serial Port Profile UUID', () {
      expect(BtcUuid.spp, '00001101-0000-1000-8000-00805F9B34FB');
    });
  });
}
