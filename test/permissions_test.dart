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

const _any = {BtcPermission.scan, BtcPermission.connect};

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

        expect(await platform.checkPermissions(_any), status);
      });
    }

    test('reads an unrecognised native status as notRequired', () async {
      _mockChannel(platform, {'checkPermissions': 'someFutureStatus'});

      expect(
        await platform.checkPermissions(_any),
        BtcPermissionStatus.notRequired,
      );
    });

    test('reads a null status as notRequired', () async {
      _mockChannel(platform, {'checkPermissions': null});

      expect(
        await platform.checkPermissions(_any),
        BtcPermissionStatus.notRequired,
      );
    });
  });

  group('Permission Requests', () {
    test('returns the status the platform reports after prompting', () async {
      _mockChannel(platform, {'requestPermissions': 'granted'});

      expect(
          await platform.requestPermissions(_any), BtcPermissionStatus.granted);
    });

    test('surfaces a permanent denial rather than reporting success', () async {
      _mockChannel(platform, {'requestPermissions': 'permanentlyDenied'});

      expect(
        await platform.requestPermissions(_any),
        BtcPermissionStatus.permanentlyDenied,
      );
    });

    test('sends the requested scopes to the platform by name', () async {
      final log = _mockChannel(platform, {'requestPermissions': 'granted'});

      await platform.requestPermissions({BtcPermission.connect});
      await platform.requestPermissions(
        {BtcPermission.scan, BtcPermission.advertise},
      );

      expect(log[0].arguments, {
        'permissions': ['connect'],
      });
      expect(log[1].arguments, {
        'permissions': ['scan', 'advertise'],
      });
    });

    test('asks only for connect when that is all the caller wants', () async {
      final log = _mockChannel(platform, {'checkPermissions': 'granted'});

      await platform.checkPermissions({BtcPermission.connect});

      final sent = (log.single.arguments as Map)['permissions'] as List;
      expect(sent, isNot(contains('scan')));
      expect(sent, ['connect']);
    });

    test('carries no arguments on the calls that take none', () async {
      final log = _mockChannel(platform, {
        'openAppSettings': true,
        'isLocationServiceRequired': true,
        'isLocationServiceEnabled': false,
        'openLocationSettings': true,
      });

      await platform.openAppSettings();
      await platform.isLocationServiceRequired();
      await platform.isLocationServiceEnabled();
      await platform.openLocationSettings();

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
        platform.requestPermissions(_any),
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
        platform.requestPermissions(_any),
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

  group('Location Services', () {
    test('reports whether scanning also needs the system toggle', () async {
      _mockChannel(platform, {'isLocationServiceRequired': true});
      expect(await platform.isLocationServiceRequired(), isTrue);

      _mockChannel(platform, {'isLocationServiceRequired': false});
      expect(await platform.isLocationServiceRequired(), isFalse);
    });

    test('reports whether the toggle is on', () async {
      _mockChannel(platform, {'isLocationServiceEnabled': false});

      expect(await platform.isLocationServiceEnabled(), isFalse);
    });

    test('assumes the toggle is on where it does not apply', () async {
      _mockChannel(platform, const {},
          notImplemented: {'isLocationServiceEnabled'});

      expect(await platform.isLocationServiceEnabled(), isTrue);
    });

    test('assumes it is not required where it does not apply', () async {
      _mockChannel(platform, const {},
          notImplemented: {'isLocationServiceRequired'});

      expect(await platform.isLocationServiceRequired(), isFalse);
    });

    test('reports whether the settings screen opened', () async {
      _mockChannel(platform, {'openLocationSettings': true});

      expect(await platform.openLocationSettings(), isTrue);
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
        await platform.checkPermissions(_any),
        BtcPermissionStatus.notRequired,
      );
      expect(
        await platform.requestPermissions(_any),
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
      expect(await bluetooth.isLocationServiceRequired(), isTrue);
      expect(await bluetooth.isLocationServiceEnabled(), isFalse);
      expect(await bluetooth.openLocationSettings(), isTrue);
      expect(fake.calls, [
        'check',
        'request',
        'settings',
        'locationRequired',
        'locationEnabled',
        'locationSettings',
      ]);
    });

    test('defaults to scan plus connect, and honours an explicit set',
        () async {
      final fake = _RecordingPlatform();
      FlutterClassicBluetoothPlatform.instance = fake;
      addTearDown(() {
        FlutterClassicBluetoothPlatform.instance =
            MethodChannelFlutterClassicBluetooth();
      });
      final bluetooth = FlutterClassicBluetooth();

      await bluetooth.checkPermissions();
      await bluetooth.checkPermissions(
        permissions: {BtcPermission.advertise},
      );

      expect(fake.scopes[0], {BtcPermission.scan, BtcPermission.connect});
      expect(fake.scopes[1], {BtcPermission.advertise});
    });

    test('the base platform interface leaves them unimplemented', () {
      final platform = _UnimplementedPlatform();

      expect(() => platform.checkPermissions(_any), throwsUnimplementedError);
      expect(() => platform.requestPermissions(_any), throwsUnimplementedError);
      expect(() => platform.openAppSettings(), throwsUnimplementedError);
      expect(
          () => platform.isLocationServiceRequired(), throwsUnimplementedError);
      expect(
          () => platform.isLocationServiceEnabled(), throwsUnimplementedError);
      expect(() => platform.openLocationSettings(), throwsUnimplementedError);
    });
  });
}

class _RecordingPlatform extends FlutterClassicBluetoothPlatform {
  final calls = <String>[];
  final scopes = <Set<BtcPermission>>[];

  @override
  Future<BtcPermissionStatus> checkPermissions(
      Set<BtcPermission> permissions) async {
    calls.add('check');
    scopes.add(permissions);
    return BtcPermissionStatus.denied;
  }

  @override
  Future<BtcPermissionStatus> requestPermissions(
      Set<BtcPermission> permissions) async {
    calls.add('request');
    scopes.add(permissions);
    return BtcPermissionStatus.granted;
  }

  @override
  Future<bool> openAppSettings() async {
    calls.add('settings');
    return true;
  }

  @override
  Future<bool> isLocationServiceRequired() async {
    calls.add('locationRequired');
    return true;
  }

  @override
  Future<bool> isLocationServiceEnabled() async {
    calls.add('locationEnabled');
    return false;
  }

  @override
  Future<bool> openLocationSettings() async {
    calls.add('locationSettings');
    return true;
  }
}

class _UnimplementedPlatform extends FlutterClassicBluetoothPlatform {}
