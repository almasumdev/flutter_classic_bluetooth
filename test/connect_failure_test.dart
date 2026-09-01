import 'package:flutter/services.dart';
import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';
import 'package:flutter_test/flutter_test.dart';

/// Makes the platform answer `connect` with a failure carrying [cause].
void _failConnectWith(String? cause, {String message = 'Connection failed'}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('flutter_classic_bluetooth/methods'),
    (call) async {
      if (call.method != 'connect') return null;
      throw PlatformException(
        code: 'connectionFailed',
        message: message,
        details: <String, dynamic>{
          'address': 'AA:BB:CC:DD:EE:FF',
          if (cause != null) 'cause': cause,
        },
      );
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter_classic_bluetooth/methods'),
      null,
    );
  });

  Future<BtcConnectionException> connectAndCatch() async {
    try {
      await FlutterClassicBluetooth().connect(
        address: 'AA:BB:CC:DD:EE:FF',
      );
    } on BtcConnectionException catch (e) {
      return e;
    }
    fail('connect should have thrown');
  }

  group('Connect Failure Cause', () {
    test('every platform tag maps to its cause', () async {
      const cases = {
        'adapterOff': BtcConnectFailure.adapterOff,
        'notPaired': BtcConnectFailure.notPaired,
        'permissionDenied': BtcConnectFailure.permissionDenied,
        'unreachable': BtcConnectFailure.unreachable,
        'serviceNotSupported': BtcConnectFailure.serviceNotSupported,
        'busy': BtcConnectFailure.busy,
        'timeout': BtcConnectFailure.timeout,
      };
      for (final entry in cases.entries) {
        _failConnectWith(entry.key);
        final e = await connectAndCatch();
        expect(e.cause, entry.value, reason: 'tag ${entry.key}');
      }
    });

    test('an absent cause degrades to unknown rather than throwing', () async {
      _failConnectWith(null);
      final e = await connectAndCatch();
      expect(e.cause, BtcConnectFailure.unknown);
    });

    test('an unrecognised tag degrades to unknown', () async {
      _failConnectWith('somethingNewFromAFuturePlatform');
      final e = await connectAndCatch();
      expect(e.cause, BtcConnectFailure.unknown);
    });

    test('the address still comes through alongside the cause', () async {
      _failConnectWith('notPaired');
      final e = await connectAndCatch();
      expect(e.address, 'AA:BB:CC:DD:EE:FF');
      expect(e.message, 'Connection failed');
    });

    test('toString names the cause, so a bare log is still useful', () async {
      _failConnectWith('unreachable');
      final e = await connectAndCatch();
      expect(e.toString(), contains('unreachable'));
      expect(e.toString(), contains('AA:BB:CC:DD:EE:FF'));
    });

    test('it is still catchable as BtcException', () async {
      _failConnectWith('busy');
      Object? caught;
      try {
        await FlutterClassicBluetooth().connect(
          address: 'AA:BB:CC:DD:EE:FF',
        );
      } on BtcException catch (e) {
        caught = e;
      }
      expect(caught, isA<BtcConnectionException>());
    });
  });

  group('Connect Failure Semantics', () {
    test('only the transient causes are retryable', () {
      expect(BtcConnectFailure.unreachable.isRetryable, isTrue);
      expect(BtcConnectFailure.busy.isRetryable, isTrue);
      expect(BtcConnectFailure.timeout.isRetryable, isTrue);

      expect(BtcConnectFailure.notPaired.isRetryable, isFalse);
      expect(BtcConnectFailure.adapterOff.isRetryable, isFalse);
      expect(BtcConnectFailure.permissionDenied.isRetryable, isFalse);
      expect(BtcConnectFailure.serviceNotSupported.isRetryable, isFalse);
      expect(BtcConnectFailure.unknown.isRetryable, isFalse);
    });

    test('every cause has a usable description', () {
      for (final cause in BtcConnectFailure.values) {
        expect(cause.description, isNotEmpty, reason: '$cause');
        expect(cause.description, endsWith('.'), reason: '$cause');
      }
    });
  });
}
