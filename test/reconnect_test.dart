import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';

import 'mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BtcReconnectPolicy', () {
    test('defaults retry forever with 1s→30s backoff', () {
      const p = BtcReconnectPolicy();
      expect(p.maxAttempts, isNull);
      expect(p.initialBackoff, const Duration(seconds: 1));
      expect(p.maxBackoff, const Duration(seconds: 30));
      expect(p.connectTimeout, const Duration(seconds: 15));
    });

    test('backoffForAttempt is exponential and capped', () {
      const p = BtcReconnectPolicy(
        initialBackoff: Duration(seconds: 1),
        maxBackoff: Duration(seconds: 8),
        backoffMultiplier: 2.0,
      );
      expect(p.backoffForAttempt(1), const Duration(seconds: 1));
      expect(p.backoffForAttempt(2), const Duration(seconds: 2));
      expect(p.backoffForAttempt(3), const Duration(seconds: 4));
      expect(p.backoffForAttempt(4), const Duration(seconds: 8));
      expect(p.backoffForAttempt(5), const Duration(seconds: 8)); // capped
      expect(p.backoffForAttempt(0), const Duration(seconds: 1)); // guarded
    });
  });

  group('connectWithReconnect validation', () {
    setUp(() {
      FlutterClassicBluetoothPlatform.instance =
          MockFlutterClassicBluetoothPlatform();
    });

    test('throws on invalid address', () {
      expect(
        () => FlutterClassicBluetooth().connectWithReconnect(address: 'bad'),
        throwsA(isA<BtcAddressException>()),
      );
    });

    test('throws on invalid uuid', () {
      expect(
        () => FlutterClassicBluetooth().connectWithReconnect(
          address: 'AA:BB:CC:DD:EE:FF',
          uuid: 'nope',
        ),
        throwsA(isA<BtcUuidException>()),
      );
    });
  });

  group('BtcReconnectingConnection', () {
    test('initial state is connecting before it is started', () {
      final link = BtcReconnectingConnection(
        address: 'AA:BB:CC:DD:EE:FF',
        connector: () async => throw const BtcConnectionException('not called'),
      );
      addTearDown(link.close);
      expect(link.currentState, BtcReconnectState.connecting);
      expect(link.isConnected, isFalse);
      expect(link.connection, isNull);
    });

    test('send throws when not connected', () {
      final link = BtcReconnectingConnection(
        address: 'AA:BB:CC:DD:EE:FF',
        connector: () async => throw const BtcConnectionException('not called'),
      );
      addTearDown(link.close);
      expect(
        () => link.sendString('hi'),
        throwsA(isA<BtcConnectionException>()),
      );
    });

    test('retries with backoff then fails after maxAttempts', () async {
      var calls = 0;
      final link = BtcReconnectingConnection(
        address: 'AA:BB:CC:DD:EE:FF',
        connector: () async {
          calls++;
          throw const BtcConnectionException('refused');
        },
        policy: const BtcReconnectPolicy(
          maxAttempts: 2,
          initialBackoff: Duration(milliseconds: 5),
          maxBackoff: Duration(milliseconds: 5),
          backoffMultiplier: 1.0,
          connectTimeout: null,
        ),
      )..start();
      addTearDown(link.close);

      final states = <BtcReconnectState>[];
      link.state.listen(states.add);

      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(calls, 3); // initial attempt + 2 retries
      expect(link.currentState, BtcReconnectState.failed);
      expect(states, contains(BtcReconnectState.reconnecting));
      expect(states.last, BtcReconnectState.failed);
    });

    test('exposes attempts and lastError after failures', () async {
      final link = BtcReconnectingConnection(
        address: 'AA:BB:CC:DD:EE:FF',
        connector: () async => throw const BtcConnectionException('refused'),
        policy: const BtcReconnectPolicy(
          maxAttempts: 1,
          initialBackoff: Duration(milliseconds: 5),
          maxBackoff: Duration(milliseconds: 5),
          backoffMultiplier: 1.0,
          connectTimeout: null,
        ),
      )..start();
      addTearDown(link.close);

      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(link.currentState, BtcReconnectState.failed);
      expect(link.attempts, greaterThan(0));
      expect(link.lastError, isA<BtcConnectionException>());
    });

    test('close() stops further reconnects', () async {
      var calls = 0;
      final link = BtcReconnectingConnection(
        address: 'AA:BB:CC:DD:EE:FF',
        connector: () async {
          calls++;
          throw const BtcConnectionException('refused');
        },
        policy: const BtcReconnectPolicy(
          initialBackoff: Duration(milliseconds: 5),
          maxBackoff: Duration(milliseconds: 5),
          backoffMultiplier: 1.0,
          connectTimeout: null,
        ),
      )..start();

      await Future<void>.delayed(const Duration(milliseconds: 15));
      await link.close();
      final after = calls;
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(link.currentState, BtcReconnectState.closed);
      expect(calls, after); // no attempts after close
    });
  });
}
