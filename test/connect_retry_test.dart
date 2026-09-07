import 'package:flutter/services.dart';
import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('flutter_classic_bluetooth/methods');

/// Answers `connect` with a failure carrying [cause], counting the attempts.
///
/// When [succeedOnAttempt] is set, that attempt returns a connection instead.
List<int> _failWith(String cause, {int? succeedOnAttempt}) {
  final attempts = <int>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
    if (call.method != 'connect') return null;
    attempts.add(attempts.length + 1);
    if (succeedOnAttempt != null && attempts.length >= succeedOnAttempt) {
      return <String, dynamic>{'id': 1, 'address': 'AA:BB:CC:DD:EE:FF'};
    }
    throw PlatformException(
      code: 'connectionFailed',
      message: 'Connection failed',
      details: <String, dynamic>{
        'address': 'AA:BB:CC:DD:EE:FF',
        'cause': cause,
      },
    );
  });
  return attempts;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  const noWait = Duration.zero;

  group('Connect Retry', () {
    test('a transient cause is retried up to maxAttempts', () async {
      final attempts = _failWith('unreachable');
      await expectLater(
        FlutterClassicBluetooth().connectWithRetry(
          address: 'AA:BB:CC:DD:EE:FF',
          maxAttempts: 3,
          initialBackoff: noWait,
        ),
        throwsA(isA<BtcConnectionException>()),
      );
      expect(attempts.length, 3);
    });

    test('a permanent cause is not retried at all', () async {
      final attempts = _failWith('notPaired');
      await expectLater(
        FlutterClassicBluetooth().connectWithRetry(
          address: 'AA:BB:CC:DD:EE:FF',
          maxAttempts: 5,
          initialBackoff: noWait,
        ),
        throwsA(
          isA<BtcConnectionException>().having(
            (e) => e.cause,
            'cause',
            BtcConnectFailure.notPaired,
          ),
        ),
      );
      expect(
        attempts.length,
        1,
        reason: 'pairing will not fix itself by waiting',
      );
    });

    test('adapterOff and permissionDenied are not retried either', () async {
      for (final cause in ['adapterOff', 'permissionDenied']) {
        final attempts = _failWith(cause);
        await expectLater(
          FlutterClassicBluetooth().connectWithRetry(
            address: 'AA:BB:CC:DD:EE:FF',
            maxAttempts: 4,
            initialBackoff: noWait,
          ),
          throwsA(isA<BtcConnectionException>()),
        );
        expect(attempts.length, 1, reason: cause);
      }
    });

    test('it stops as soon as an attempt succeeds', () async {
      final attempts = _failWith('unreachable', succeedOnAttempt: 2);
      final conn = await FlutterClassicBluetooth().connectWithRetry(
        address: 'AA:BB:CC:DD:EE:FF',
        maxAttempts: 5,
        initialBackoff: noWait,
      );
      expect(attempts.length, 2);
      expect(conn.address, 'AA:BB:CC:DD:EE:FF');
    });

    test('maxAttempts of 1 behaves like a plain connect', () async {
      final attempts = _failWith('unreachable');
      await expectLater(
        FlutterClassicBluetooth().connectWithRetry(
          address: 'AA:BB:CC:DD:EE:FF',
          maxAttempts: 1,
          initialBackoff: noWait,
        ),
        throwsA(isA<BtcConnectionException>()),
      );
      expect(attempts.length, 1);
    });

    test('the cause from the final attempt is what propagates', () async {
      _failWith('busy');
      await expectLater(
        FlutterClassicBluetooth().connectWithRetry(
          address: 'AA:BB:CC:DD:EE:FF',
          maxAttempts: 2,
          initialBackoff: noWait,
        ),
        throwsA(
          isA<BtcConnectionException>().having(
            (e) => e.cause,
            'cause',
            BtcConnectFailure.busy,
          ),
        ),
      );
    });

    test('maxAttempts below 1 is rejected', () async {
      await expectLater(
        FlutterClassicBluetooth().connectWithRetry(
          address: 'AA:BB:CC:DD:EE:FF',
          maxAttempts: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('an invalid address still fails validation before any attempt',
        () async {
      final attempts = _failWith('unreachable');
      await expectLater(
        FlutterClassicBluetooth().connectWithRetry(
          address: 'not-a-mac',
          initialBackoff: noWait,
        ),
        throwsA(isA<BtcAddressException>()),
      );
      expect(attempts, isEmpty);
    });
  });
}
