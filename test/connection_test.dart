import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BtcStreamSink', () {
    test('throws StateError after close', () async {
      final sink = BtcStreamSink(
        connectionId: 1,
        methodChannel: const MethodChannel('flutter_classic_bluetooth/methods'),
      );

      sink.cancel();
      expect(sink.isClosed, isTrue);
      expect(
        () => sink.add(Uint8List(1)),
        throwsA(isA<StateError>()),
      );
    });

    test('isClosed is false initially', () {
      final sink = BtcStreamSink(
        connectionId: 1,
        methodChannel: const MethodChannel('flutter_classic_bluetooth/methods'),
      );
      expect(sink.isClosed, isFalse);
    });

    test('cancel marks sink as closed', () {
      final sink = BtcStreamSink(
        connectionId: 1,
        methodChannel: const MethodChannel('flutter_classic_bluetooth/methods'),
      );
      sink.cancel();
      expect(sink.isClosed, isTrue);
    });

    test('close marks sink as closed', () async {
      final sink = BtcStreamSink(
        connectionId: 1,
        methodChannel: const MethodChannel('flutter_classic_bluetooth/methods'),
      );
      await sink.close();
      expect(sink.isClosed, isTrue);
    });

    test('double close does not throw', () async {
      final sink = BtcStreamSink(
        connectionId: 1,
        methodChannel: const MethodChannel('flutter_classic_bluetooth/methods'),
      );
      await sink.close();
      await sink.close();
      expect(sink.isClosed, isTrue);
    });

    test('add sends write over method channel', () async {
      final methodChannel =
          const MethodChannel('flutter_classic_bluetooth/methods');
      final calls = <MethodCall>[];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
        calls.add(call);
        return null;
      });

      final sink = BtcStreamSink(
        connectionId: 42,
        methodChannel: methodChannel,
      );

      final data = Uint8List.fromList([1, 2, 3]);
      await sink.add(data);

      expect(calls, hasLength(1));
      expect(calls.first.method, 'write');
      expect(calls.first.arguments['id'], 42);
      expect(calls.first.arguments['data'], data);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, null);
    });

    test('writeLine appends the newline', () async {
      const methodChannel = MethodChannel('flutter_classic_bluetooth/methods');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
        calls.add(call);
        return null;
      });

      final sink = BtcStreamSink(connectionId: 9, methodChannel: methodChannel);
      await sink.writeLine('AT');

      expect(
        String.fromCharCodes(calls.single.arguments['data'] as Uint8List),
        'AT\r\n',
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, null);
    });

    test('writes are chained in order', () async {
      final methodChannel =
          const MethodChannel('flutter_classic_bluetooth/methods');
      final calls = <int>[];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
        calls.add(call.arguments['data'][0] as int);
        return null;
      });

      final sink = BtcStreamSink(
        connectionId: 1,
        methodChannel: methodChannel,
      );

      // Fire-and-forget multiple writes
      sink.add(Uint8List.fromList([1]));
      sink.add(Uint8List.fromList([2]));
      await sink.add(Uint8List.fromList([3]));

      expect(calls, [1, 2, 3]);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, null);
    });
  });

  // ── BtcConnection ────────────────────────────────────────────────────

  group('BtcConnection', () {
    test('constructor sets properties correctly', () {
      final conn = BtcConnection(
        id: 5,
        address: 'AA:BB:CC:DD:EE:FF',
        methodChannel: const MethodChannel('flutter_classic_bluetooth/methods'),
      );

      expect(conn.id, 5);
      expect(conn.address, 'AA:BB:CC:DD:EE:FF');
      expect(conn.isConnected, isTrue);
      expect(conn.state, BtcConnectionState.connected);
    });

    test('output sink is a BtcStreamSink', () {
      final conn = BtcConnection(
        id: 1,
        address: 'AA:BB:CC:DD:EE:FF',
        methodChannel: const MethodChannel('flutter_classic_bluetooth/methods'),
      );

      expect(conn.output, isA<BtcStreamSink>());
      expect(conn.output.isClosed, isFalse);
    });

    test('dispose cancels output sink', () {
      final conn = BtcConnection(
        id: 1,
        address: 'AA:BB:CC:DD:EE:FF',
        methodChannel: const MethodChannel('flutter_classic_bluetooth/methods'),
      );

      conn.dispose();
      expect(conn.output.isClosed, isTrue);
    });

    test('sendAndReceive writes the command and returns the response line',
        () async {
      const method = MethodChannel('flutter_classic_bluetooth/methods');
      const dataChannel =
          EventChannel('flutter_classic_bluetooth/connection/1');
      const stateChannel =
          EventChannel('flutter_classic_bluetooth/connection_state/1');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

      final writes = <String>[];
      messenger.setMockMethodCallHandler(method, (call) async {
        if (call.method == 'write') {
          writes.add(String.fromCharCodes(call.arguments['data'] as Uint8List));
        }
        return null;
      });
      MockStreamHandlerEventSink? dataSink;
      messenger.setMockStreamHandler(
        dataChannel,
        MockStreamHandler.inline(onListen: (args, sink) => dataSink = sink),
      );
      messenger.setMockStreamHandler(
        stateChannel,
        MockStreamHandler.inline(onListen: (args, sink) {}),
      );

      final conn = BtcConnection(
        id: 1,
        address: 'AA:BB:CC:DD:EE:FF',
        methodChannel: method,
      );

      final future =
          conn.sendAndReceive('AT', timeout: const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      dataSink!.success(Uint8List.fromList('OK\r\n'.codeUnits));

      expect(await future, 'OK');
      expect(writes, ['AT\r\n']);

      conn.dispose();
      messenger.setMockMethodCallHandler(method, null);
      messenger.setMockStreamHandler(dataChannel, null);
      messenger.setMockStreamHandler(stateChannel, null);
    });

    test('sendAndReceive throws BtcTimeoutException when no response arrives',
        () async {
      const method = MethodChannel('flutter_classic_bluetooth/methods');
      const dataChannel =
          EventChannel('flutter_classic_bluetooth/connection/2');
      const stateChannel =
          EventChannel('flutter_classic_bluetooth/connection_state/2');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

      messenger.setMockMethodCallHandler(method, (call) async => null);
      messenger.setMockStreamHandler(
        dataChannel,
        MockStreamHandler.inline(onListen: (args, sink) {}),
      );
      messenger.setMockStreamHandler(
        stateChannel,
        MockStreamHandler.inline(onListen: (args, sink) {}),
      );

      final conn = BtcConnection(
        id: 2,
        address: 'AA:BB:CC:DD:EE:FF',
        methodChannel: method,
      );

      await expectLater(
        conn.sendAndReceive('AT', timeout: const Duration(milliseconds: 50)),
        throwsA(isA<BtcTimeoutException>()),
      );

      conn.dispose();
      messenger.setMockMethodCallHandler(method, null);
      messenger.setMockStreamHandler(dataChannel, null);
      messenger.setMockStreamHandler(stateChannel, null);
    });

    test('readRssi sends getConnectionRssi and returns the value', () async {
      const method = MethodChannel('flutter_classic_bluetooth/methods');
      const dataChannel =
          EventChannel('flutter_classic_bluetooth/connection/7');
      const stateChannel =
          EventChannel('flutter_classic_bluetooth/connection_state/7');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

      MethodCall? seen;
      messenger.setMockMethodCallHandler(method, (call) async {
        seen = call;
        return -42;
      });
      messenger.setMockStreamHandler(
          dataChannel, MockStreamHandler.inline(onListen: (args, sink) {}));
      messenger.setMockStreamHandler(
          stateChannel, MockStreamHandler.inline(onListen: (args, sink) {}));

      final conn = BtcConnection(
          id: 7, address: 'AA:BB:CC:DD:EE:FF', methodChannel: method);

      expect(await conn.readRssi(), -42);
      expect(seen?.method, 'getConnectionRssi');
      expect(seen?.arguments['id'], 7);

      conn.dispose();
      messenger.setMockMethodCallHandler(method, null);
      messenger.setMockStreamHandler(dataChannel, null);
      messenger.setMockStreamHandler(stateChannel, null);
    });

    test('readRssi returns null when the platform has no sample', () async {
      const method = MethodChannel('flutter_classic_bluetooth/methods');
      const dataChannel =
          EventChannel('flutter_classic_bluetooth/connection/8');
      const stateChannel =
          EventChannel('flutter_classic_bluetooth/connection_state/8');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

      messenger.setMockMethodCallHandler(method, (call) async => null);
      messenger.setMockStreamHandler(
          dataChannel, MockStreamHandler.inline(onListen: (args, sink) {}));
      messenger.setMockStreamHandler(
          stateChannel, MockStreamHandler.inline(onListen: (args, sink) {}));

      final conn = BtcConnection(
          id: 8, address: 'AA:BB:CC:DD:EE:FF', methodChannel: method);

      expect(await conn.readRssi(), isNull);

      conn.dispose();
      messenger.setMockMethodCallHandler(method, null);
      messenger.setMockStreamHandler(dataChannel, null);
      messenger.setMockStreamHandler(stateChannel, null);
    });

    test('readRssi maps an unsupported PlatformException to unsupported',
        () async {
      const method = MethodChannel('flutter_classic_bluetooth/methods');
      const dataChannel =
          EventChannel('flutter_classic_bluetooth/connection/9');
      const stateChannel =
          EventChannel('flutter_classic_bluetooth/connection_state/9');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

      messenger.setMockMethodCallHandler(method, (call) async {
        throw PlatformException(
          code: 'unsupported',
          message: 'no RSSI on Windows',
          details: {'feature': 'getConnectionRssi', 'platform': 'Windows'},
        );
      });
      messenger.setMockStreamHandler(
          dataChannel, MockStreamHandler.inline(onListen: (args, sink) {}));
      messenger.setMockStreamHandler(
          stateChannel, MockStreamHandler.inline(onListen: (args, sink) {}));

      final conn = BtcConnection(
          id: 9, address: 'AA:BB:CC:DD:EE:FF', methodChannel: method);

      await expectLater(
        conn.readRssi(),
        throwsA(isA<BtcUnsupportedException>()
            .having((e) => e.platform, 'platform', 'Windows')),
      );

      conn.dispose();
      messenger.setMockMethodCallHandler(method, null);
      messenger.setMockStreamHandler(dataChannel, null);
      messenger.setMockStreamHandler(stateChannel, null);
    });

    test('readRssi maps a MissingPluginException to unsupported', () async {
      const method = MethodChannel('flutter_classic_bluetooth/methods');
      const dataChannel =
          EventChannel('flutter_classic_bluetooth/connection/10');
      const stateChannel =
          EventChannel('flutter_classic_bluetooth/connection_state/10');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

      // No method handler → invokeMethod throws MissingPluginException.
      messenger.setMockMethodCallHandler(method, null);
      messenger.setMockStreamHandler(
          dataChannel, MockStreamHandler.inline(onListen: (args, sink) {}));
      messenger.setMockStreamHandler(
          stateChannel, MockStreamHandler.inline(onListen: (args, sink) {}));

      final conn = BtcConnection(
          id: 10, address: 'AA:BB:CC:DD:EE:FF', methodChannel: method);

      await expectLater(
        conn.readRssi(),
        throwsA(isA<BtcUnsupportedException>()),
      );

      conn.dispose();
      messenger.setMockStreamHandler(dataChannel, null);
      messenger.setMockStreamHandler(stateChannel, null);
    });
  });

  // ── BtcServerSocket ──────────────────────────────────────────────────

  group('BtcServerSocket', () {
    test('constructor sets properties correctly', () {
      final server = BtcServerSocket(
        id: 3,
        uuid: '00001101-0000-1000-8000-00805F9B34FB',
        serviceName: 'TestService',
        methodChannel: const MethodChannel('flutter_classic_bluetooth/methods'),
      );

      expect(server.id, 3);
      expect(server.uuid, '00001101-0000-1000-8000-00805F9B34FB');
      expect(server.serviceName, 'TestService');
    });

    test('close sends stopServer method call', () async {
      final methodChannel =
          const MethodChannel('flutter_classic_bluetooth/methods');
      final calls = <MethodCall>[];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
        calls.add(call);
        return null;
      });

      final server = BtcServerSocket(
        id: 7,
        uuid: '00001101-0000-1000-8000-00805F9B34FB',
        serviceName: 'Test',
        methodChannel: methodChannel,
      );

      await server.close();

      expect(calls, hasLength(1));
      expect(calls.first.method, 'stopServer');
      expect(calls.first.arguments, {'id': 7});

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, null);
    });
  });

  // ── Enum Values ───────────────────────────────────────────────────────
}
