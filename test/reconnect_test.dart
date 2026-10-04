import 'package:flutter/services.dart';
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
  group('waitConnected', () {
    /// A connection object good enough to stand in for a live link.
    BtcConnection fakeConnection() => BtcConnection(
      id: 1,
      address: 'AA:BB:CC:DD:EE:FF',
      methodChannel: const MethodChannel('flutter_classic_bluetooth/methods'),
    );

    test('returns as soon as the link comes up', () async {
      var attempts = 0;
      final link = BtcReconnectingConnection(
        address: 'AA:BB:CC:DD:EE:FF',
        connector: () async {
          // Refuse once so the caller really has to wait.
          if (attempts++ == 0) {
            throw const BtcConnectionException('refused');
          }
          return fakeConnection();
        },
        policy: const BtcReconnectPolicy(
          initialBackoff: Duration(milliseconds: 5),
          maxBackoff: Duration(milliseconds: 5),
          backoffMultiplier: 1.0,
          connectTimeout: null,
        ),
      )..start();
      addTearDown(link.close);

      await link.waitConnected(timeout: const Duration(seconds: 2));
      expect(link.isConnected, isTrue);
    });

    test('returns straight away when already connected', () async {
      final link = BtcReconnectingConnection(
        address: 'AA:BB:CC:DD:EE:FF',
        connector: () async => fakeConnection(),
      )..start();
      addTearDown(link.close);

      await link.waitConnected();
      // A second call must not hang waiting for another state change.
      await link.waitConnected(timeout: const Duration(milliseconds: 50));
      expect(link.isConnected, isTrue);
    });

    test('a write placed behind it goes out once the link is up', () async {
      var attempts = 0;
      final link = BtcReconnectingConnection(
        address: 'AA:BB:CC:DD:EE:FF',
        connector: () async {
          if (attempts++ == 0) {
            throw const BtcConnectionException('refused');
          }
          return fakeConnection();
        },
        policy: const BtcReconnectPolicy(
          initialBackoff: Duration(milliseconds: 5),
          maxBackoff: Duration(milliseconds: 5),
          backoffMultiplier: 1.0,
          connectTimeout: null,
        ),
      )..start();
      addTearDown(link.close);

      // Catch the write at the channel so it needs no real device.
      const channel = MethodChannel('flutter_classic_bluetooth/methods');
      final written = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            written.add(call.method);
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      // Without the wait this throws, which is what the doc used to leave to
      // the caller to handle.
      expect(
        () => link.sendString('hi'),
        throwsA(isA<BtcConnectionException>()),
      );
      await link.waitConnected(timeout: const Duration(seconds: 2));
      await link.sendString('hi');
      expect(written, contains('write'));
    });

    test('throws once the retries are exhausted', () async {
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

      await expectLater(
        link.waitConnected(timeout: const Duration(seconds: 2)),
        throwsA(isA<BtcConnectionException>()),
      );
    });

    test('throws when it has already given up', () async {
      final link = BtcReconnectingConnection(
        address: 'AA:BB:CC:DD:EE:FF',
        connector: () async => throw const BtcConnectionException('refused'),
        policy: const BtcReconnectPolicy(
          maxAttempts: 0,
          initialBackoff: Duration(milliseconds: 5),
          maxBackoff: Duration(milliseconds: 5),
          backoffMultiplier: 1.0,
          connectTimeout: null,
        ),
      )..start();
      addTearDown(link.close);

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(link.currentState, BtcReconnectState.failed);
      await expectLater(
        link.waitConnected(),
        throwsA(isA<BtcConnectionException>()),
      );
    });

    test('throws when the link is closed while waiting', () async {
      final link = BtcReconnectingConnection(
        address: 'AA:BB:CC:DD:EE:FF',
        connector: () async => throw const BtcConnectionException('refused'),
        policy: const BtcReconnectPolicy(
          initialBackoff: Duration(milliseconds: 50),
          maxBackoff: Duration(milliseconds: 50),
          backoffMultiplier: 1.0,
          connectTimeout: null,
        ),
      )..start();

      // The matcher is attached before the close, so the rejection is awaited
      // rather than surfacing as an unhandled error in the gap.
      final waiting = expectLater(
        link.waitConnected(),
        throwsA(isA<BtcConnectionException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await link.close();
      await waiting;
    });

    test('throws when it is already closed', () async {
      final link = BtcReconnectingConnection(
        address: 'AA:BB:CC:DD:EE:FF',
        connector: () async => throw const BtcConnectionException('refused'),
      );
      await link.close();
      await expectLater(
        link.waitConnected(),
        throwsA(isA<BtcConnectionException>()),
      );
    });

    test('throws when the timeout runs out first', () async {
      final link = BtcReconnectingConnection(
        address: 'AA:BB:CC:DD:EE:FF',
        connector: () async => throw const BtcConnectionException('refused'),
        policy: const BtcReconnectPolicy(
          initialBackoff: Duration(seconds: 30),
          maxBackoff: Duration(seconds: 30),
          backoffMultiplier: 1.0,
          connectTimeout: null,
        ),
      )..start();
      addTearDown(link.close);

      await expectLater(
        link.waitConnected(timeout: const Duration(milliseconds: 20)),
        throwsA(isA<BtcConnectionException>()),
      );
    });
  });
}
