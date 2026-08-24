import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';

/// Installs a handler that answers the permission methods with [replies] and
/// records every call it receives.
List<MethodCall> _mockChannel(
  MethodChannelFlutterClassicBluetooth platform,
  Map<String, Object?> replies, {
  Set<String> notImplemented = const {},
}) {
  final log = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(platform.methodChannel, (call) async {
    log.add(call);
    if (notImplemented.contains(call.method)) {
      throw MissingPluginException(
        'No implementation found for method ${call.method}',
      );
    }
    if (replies.containsKey(call.method)) return replies[call.method];
    throw PlatformException(code: 'unexpected', message: call.method);
  });
  return log;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannelFlutterClassicBluetooth platform;

  setUp(() => platform = MethodChannelFlutterClassicBluetooth());

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform.methodChannel, null);
  });

  group('Permission Status Decoding', () {
    for (final status in BtcPermissionStatus.values) {
      test('decodes ${status.name} from the native name', () async {
        _mockChannel(platform, {'checkPermissions': status.name});

        expect(await platform.checkPermissions(), status);
      });
    }

    test('reads an unrecognised native status as notRequired', () async {
      _mockChannel(platform, {'checkPermissions': 'someFutureStatus'});

      expect(
        await platform.checkPermissions(),
        BtcPermissionStatus.notRequired,
      );
    });

    test('reads a null status as notRequired', () async {
      _mockChannel(platform, {'checkPermissions': null});

      expect(
        await platform.checkPermissions(),
        BtcPermissionStatus.notRequired,
      );
    });
  });

  group('Permission Requests', () {
    test('returns the status the platform reports after prompting', () async {
      _mockChannel(platform, {'requestPermissions': 'granted'});

      expect(await platform.requestPermissions(), BtcPermissionStatus.granted);
    });

    test('surfaces a permanent denial rather than reporting success', () async {
      _mockChannel(platform, {'requestPermissions': 'permanentlyDenied'});

      expect(
        await platform.requestPermissions(),
        BtcPermissionStatus.permanentlyDenied,
      );
    });

    test('invokes the channel method by name, with no arguments', () async {
      final log = _mockChannel(platform, {
        'checkPermissions': 'granted',
        'requestPermissions': 'granted',
        'openAppSettings': true,
      });

      await platform.checkPermissions();
      await platform.requestPermissions();
      await platform.openAppSettings();

      expect(log.map((c) => c.method), [
        'checkPermissions',
        'requestPermissions',
        'openAppSettings',
      ]);
      expect(log.every((c) => c.arguments == null), isTrue);
    });

    test('maps a concurrent request to a typed exception', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform.methodChannel, (call) async {
        throw PlatformException(
          code: 'pendingOperation',
          message: 'A permission request is already in progress',
        );
      });

      await expectLater(
        platform.requestPermissions(),
        throwsA(
          isA<BtcException>().having((e) => e.code, 'code', 'pendingOperation'),
        ),
      );
    });

    test('maps a missing activity to BtcPermissionException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform.methodChannel, (call) async {
        throw PlatformException(
          code: 'permissionDenied',
          message: 'No activity available to request permissions',
        );
      });

      await expectLater(
        platform.requestPermissions(),
        throwsA(isA<BtcPermissionException>()),
      );
    });
  });

  group('Opening App Settings', () {
    test('reports whether the settings page opened', () async {
      _mockChannel(platform, {'openAppSettings': true});
      expect(await platform.openAppSettings(), isTrue);

      _mockChannel(platform, {'openAppSettings': false});
      expect(await platform.openAppSettings(), isFalse);
    });

    test('reads a null reply as not opened', () async {
      _mockChannel(platform, {'openAppSettings': null});

      expect(await platform.openAppSettings(), isFalse);
    });
  });

  group('Older Native Builds', () {
    test('reports notRequired when the native side lacks the method', () async {
      _mockChannel(
        platform,
        const {},
        notImplemented: {'checkPermissions', 'requestPermissions'},
      );

      expect(
        await platform.checkPermissions(),
        BtcPermissionStatus.notRequired,
      );
      expect(
        await platform.requestPermissions(),
        BtcPermissionStatus.notRequired,
      );
    });

    test('reports false for openAppSettings when unimplemented', () async {
      _mockChannel(platform, const {}, notImplemented: {'openAppSettings'});

      expect(await platform.openAppSettings(), isFalse);
    });
  });

  group('Plugin Surface', () {
    test('delegates each permission call to the platform instance', () async {
      final fake = _RecordingPlatform();
      FlutterClassicBluetoothPlatform.instance = fake;
      addTearDown(() {
        FlutterClassicBluetoothPlatform.instance =
            MethodChannelFlutterClassicBluetooth();
      });
      final bluetooth = FlutterClassicBluetooth();

      expect(await bluetooth.checkPermissions(), BtcPermissionStatus.denied);
      expect(await bluetooth.requestPermissions(), BtcPermissionStatus.granted);
      expect(await bluetooth.openAppSettings(), isTrue);
      expect(fake.calls, ['check', 'request', 'settings']);
    });

    test('the base platform interface leaves them unimplemented', () {
      final platform = _UnimplementedPlatform();

      expect(() => platform.checkPermissions(), throwsUnimplementedError);
      expect(() => platform.requestPermissions(), throwsUnimplementedError);
      expect(() => platform.openAppSettings(), throwsUnimplementedError);
    });
  });
}

class _RecordingPlatform extends FlutterClassicBluetoothPlatform {
  final calls = <String>[];

  @override
  Future<BtcPermissionStatus> checkPermissions() async {
    calls.add('check');
    return BtcPermissionStatus.denied;
  }

  @override
  Future<BtcPermissionStatus> requestPermissions() async {
    calls.add('request');
    return BtcPermissionStatus.granted;
  }

  @override
  Future<bool> openAppSettings() async {
    calls.add('settings');
    return true;
  }
}

class _UnimplementedPlatform extends FlutterClassicBluetoothPlatform {}
