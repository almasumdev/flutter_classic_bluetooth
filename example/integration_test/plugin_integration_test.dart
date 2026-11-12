import 'package:flutter/foundation.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';
import 'package:flutter_classic_bluetooth_example/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ── Plugin API Tests ─────────────────────────────────────────────────

  group('Plugin API: Adapter', () {
    late FlutterClassicBluetooth bluetooth;

    setUp(() {
      bluetooth = FlutterClassicBluetooth();
    });

    testWidgets('singleton instance', (tester) async {
      final a = FlutterClassicBluetooth();
      final b = FlutterClassicBluetooth();
      expect(identical(a, b), isTrue);
    });

    testWidgets('isSupported returns a bool', (tester) async {
      final result = await bluetooth.isSupported();
      expect(result, isA<bool>());
    });

    testWidgets('isEnabled returns a bool', (tester) async {
      final result = await bluetooth.isEnabled();
      expect(result, isA<bool>());
    });

    testWidgets('getAdapterName returns String or null', (tester) async {
      try {
        final name = await bluetooth.getAdapterName();
        expect(name, anyOf(isA<String>(), isNull));
      } on BtcException {
        // Reading the adapter name needs runtime BT permission on Android 12+;
        // a fresh headless install may not have it granted. Acceptable here.
      }
    });

    testWidgets('getAdapterAddress returns String or null', (tester) async {
      try {
        final address = await bluetooth.getAdapterAddress();
        expect(address, anyOf(isA<String>(), isNull));
      } on BtcException {
        // Same runtime-permission caveat as getAdapterName.
      }
    });

    testWidgets('enableBluetooth returns bool or throws', (tester) async {
      try {
        final result = await bluetooth.enableBluetooth();
        expect(result, isA<bool>());
      } on BtcUnsupportedException {
        // Expected on platforms that don't support this
      } on BtcException {
        // BT error is acceptable
      }
    });

    testWidgets('disableBluetooth returns bool or throws', (tester) async {
      try {
        final result = await bluetooth.disableBluetooth();
        expect(result, isA<bool>());
      } on BtcUnsupportedException {
        // Expected on platforms that don't support this
      } on BtcException {
        // BT error is acceptable
      }
    });
  });

  group('Plugin API: Discovery', () {
    late FlutterClassicBluetooth bluetooth;

    setUp(() {
      bluetooth = FlutterClassicBluetooth();
    });

    testWidgets('isDiscovering returns a bool', (tester) async {
      final result = await bluetooth.isDiscovering();
      expect(result, isA<bool>());
    });

    testWidgets('startDiscovery and stopDiscovery do not throw', (
      tester,
    ) async {
      try {
        await bluetooth.startDiscovery();
        // Give it a moment then stop
        await bluetooth.stopDiscovery();
      } on BtcUnsupportedException {
        // Unsupported on iOS
      } on BtcDisabledException {
        // BT may be off
      } on BtcException {
        // Acceptable
      }
    });

    testWidgets('scan() returns a de-duplicated device list', (tester) async {
      try {
        final devices = await bluetooth.scan(
          timeout: const Duration(seconds: 3),
        );
        expect(devices, isA<List<BtcDevice>>());
        // Results are keyed by address, so there are no duplicates.
        final addresses = devices.map((d) => d.address).toList();
        expect(addresses.toSet().length, addresses.length);
      } on BtcUnsupportedException {
        // Discovery unsupported (iOS)
      } on BtcDisabledException {
        // BT may be off
      } on BtcException {
        // Permission denied / adapter error, acceptable in CI-less runs
      }
    });
  });

  group('Plugin API: Pairing', () {
    late FlutterClassicBluetooth bluetooth;

    setUp(() {
      bluetooth = FlutterClassicBluetooth();
    });

    testWidgets('getPairedDevices returns a list', (tester) async {
      try {
        final devices = await bluetooth.getPairedDevices();
        expect(devices, isA<List<BtcDevice>>());
        for (final device in devices) {
          expect(device.address, isNotEmpty);
        }
      } on BtcException {
        // BT may be disabled
      }
    });

    testWidgets('bondDevice validates MAC address', (tester) async {
      expect(
        () => bluetooth.bondDevice('invalid'),
        throwsA(isA<BtcAddressException>()),
      );
    });

    testWidgets('unbondDevice validates MAC address', (tester) async {
      expect(
        () => bluetooth.unbondDevice('not-a-mac'),
        throwsA(isA<BtcAddressException>()),
      );
    });
  });

  group('Plugin API: Connection validation', () {
    late FlutterClassicBluetooth bluetooth;

    setUp(() {
      bluetooth = FlutterClassicBluetooth();
    });

    testWidgets('connect validates MAC address', (tester) async {
      expect(
        () => bluetooth.connect(
          address: 'bad-address',
          uuid: '00001101-0000-1000-8000-00805F9B34FB',
        ),
        throwsA(isA<BtcAddressException>()),
      );
    });

    testWidgets('connect validates UUID format', (tester) async {
      expect(
        () =>
            bluetooth.connect(address: 'AA:BB:CC:DD:EE:FF', uuid: 'not-a-uuid'),
        throwsA(isA<BtcUuidException>()),
      );
    });

    testWidgets('startServer validates UUID format', (tester) async {
      expect(
        () => bluetooth.startServer(uuid: 'bad-uuid', serviceName: 'Test'),
        throwsA(isA<BtcUuidException>()),
      );
    });
  });

  group('Plugin API: Capabilities', () {
    late FlutterClassicBluetooth bluetooth;

    setUp(() {
      bluetooth = FlutterClassicBluetooth();
    });

    testWidgets('getPlatformCapabilities returns all fields', (tester) async {
      final caps = await bluetooth.getPlatformCapabilities();
      expect(caps, isA<BtcPlatformCapabilities>());
      expect(caps.canEnableBluetooth, isA<bool>());
      expect(caps.canDisableBluetooth, isA<bool>());
      expect(caps.canDiscoverDevices, isA<bool>());
      expect(caps.canGetPairedDevices, isA<bool>());
      expect(caps.canBondDevices, isA<bool>());
      expect(caps.canUnbondDevices, isA<bool>());
      expect(caps.canCreateServer, isA<bool>());
      expect(caps.canSetDiscoverable, isA<bool>());
      expect(caps.supportsMultipleConnections, isA<bool>());
      expect(caps.supportsSecureConnection, isA<bool>());
      expect(caps.supportsInsecureConnection, isA<bool>());
      expect(caps.canReadConnectionRssi, isA<bool>());
      expect(caps.requiresMfiCertification, isA<bool>());
    });

    testWidgets('connection RSSI is macOS-only', (tester) async {
      final caps = await bluetooth.getPlatformCapabilities();
      // Only macOS exposes a public API for connection RSSI; every other
      // platform must report false so callers get a typed unsupported error.
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        expect(caps.canReadConnectionRssi, isTrue);
      } else {
        expect(caps.canReadConnectionRssi, isFalse);
      }
    });

    testWidgets('platformNote is String or null', (tester) async {
      final caps = await bluetooth.getPlatformCapabilities();
      expect(caps.platformNote, anyOf(isA<String>(), isNull));
    });

    testWidgets('setDiscoverable is reported via capabilities', (tester) async {
      // NOTE: setDiscoverable() shows an interactive system consent dialog on
      // Android and awaits the user's tap, so it can never complete in a
      // headless integration run: calling it here would hang the whole suite.
      // Verify the capability flag instead; the real call is covered by manual
      // on-device testing.
      final caps = await bluetooth.getPlatformCapabilities();
      expect(caps.canSetDiscoverable, isA<bool>());
    });
  });

  // ── App UI Tests ─────────────────────────────────────────────────────
  //
  // The example is a tab shell: a NavigationBar (phones) or NavigationRail
  // (wide screens) with Dashboard / Discover / Paired / Server / About tabs.
  // These tests drive the redesigned UI and tolerate the adapter being on,
  // off, or lacking a capability, so they pass on any real device.

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(const BluetoothExampleApp());
    await tester.pumpAndSettle();
  }

  // Taps a destination label inside whichever navigation widget the shell
  // shows (NavigationBar on phones, NavigationRail on wide screens).
  Future<void> switchTab(WidgetTester tester, String label) async {
    final inBar = find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text(label),
    );
    final inRail = find.descendant(
      of: find.byType(NavigationRail),
      matching: find.text(label),
    );
    final target = inBar.evaluate().isNotEmpty ? inBar : inRail;
    await tester.tap(target.first);
    await tester.pumpAndSettle();
  }

  group('App UI: Shell', () {
    testWidgets('builds and shows the app bar title', (tester) async {
      await pumpApp(tester);
      expect(find.text('Bluetooth Classic'), findsAtLeast(1));
    });

    testWidgets('shows a navigation bar or rail', (tester) async {
      await pumpApp(tester);
      final hasBar = find.byType(NavigationBar).evaluate().isNotEmpty;
      final hasRail = find.byType(NavigationRail).evaluate().isNotEmpty;
      expect(hasBar || hasRail, isTrue);
    });

    testWidgets('shows all five navigation destinations', (tester) async {
      await pumpApp(tester);
      for (final label in const [
        'Dashboard',
        'Discover',
        'Paired',
        'Server',
        'About',
      ]) {
        expect(find.text(label), findsAtLeast(1), reason: '$label destination');
      }
    });
  });

  group('App UI: Dashboard tab', () {
    testWidgets('shows the adapter hero or an unsupported state', (
      tester,
    ) async {
      await pumpApp(tester);
      if (find.text('Bluetooth Classic unavailable').evaluate().isNotEmpty) {
        // This device reports no Bluetooth Classic hardware.
        expect(find.text('Bluetooth Classic unavailable'), findsOneWidget);
        return;
      }
      // The adapter hero at the top shows "Adapter <state>" and a toggle.
      expect(find.textContaining('Adapter'), findsAtLeast(1));
      expect(find.textContaining(RegExp('Turn on|Turn off')), findsAtLeast(1));
    });
  });

  group('App UI: About (capabilities) tab', () {
    testWidgets('lists the platform capability rows', (tester) async {
      await pumpApp(tester);
      await switchTab(tester, 'About');

      expect(find.text('What this platform can do'), findsOneWidget);
      for (final label in const [
        'Discover devices',
        'Get paired devices',
        'Pair (bond)',
        'Unpair (unbond)',
        'Enable Bluetooth',
        'Create RFCOMM server',
        'Multiple connections',
        'Requires MFi certification',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('each of the 12 capability rows shows an on/off icon', (
      tester,
    ) async {
      await pumpApp(tester);
      await switchTab(tester, 'About');
      final on = find.byIcon(Icons.check_circle).evaluate().length;
      final off = find.byIcon(Icons.remove_circle_outline).evaluate().length;
      expect(on + off, 12);
    });
  });

  group('App UI: Server tab', () {
    testWidgets('shows the server form or an unsupported state', (
      tester,
    ) async {
      await pumpApp(tester);
      await switchTab(tester, 'Server');
      if (find.text('Server mode not supported').evaluate().isNotEmpty) {
        expect(find.text('Server mode not supported'), findsOneWidget);
        return;
      }
      expect(find.text('RFCOMM server'), findsOneWidget);
      expect(find.text('Start server'), findsOneWidget);
      expect(find.text('Secure connection'), findsOneWidget);
    });
  });

  group('App UI: Discover tab', () {
    testWidgets('shows the scan control or an appropriate empty state', (
      tester,
    ) async {
      await pumpApp(tester);
      await switchTab(tester, 'Discover');
      // Exactly one of these shows, depending on adapter/permission state.
      final canScan =
          find.text('Scan').evaluate().isNotEmpty ||
          find.text('Stop').evaluate().isNotEmpty;
      final off = find.text('Bluetooth is off').evaluate().isNotEmpty;
      final unsupported = find
          .text('Discovery not supported')
          .evaluate()
          .isNotEmpty;
      expect(canScan || off || unsupported, isTrue);
    });
  });

  group('App UI: Paired tab', () {
    testWidgets('shows the paired list, empty state, or refresh action', (
      tester,
    ) async {
      await pumpApp(tester);
      await switchTab(tester, 'Paired');
      final refreshFab = find.byIcon(Icons.refresh).evaluate().isNotEmpty;
      final empty = find.text('No paired devices').evaluate().isNotEmpty;
      final unsupported = find
          .text('Paired list not available')
          .evaluate()
          .isNotEmpty;
      final hasMac = find
          .textContaining(
            RegExp(r'[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}'),
          )
          .evaluate()
          .isNotEmpty;
      expect(refreshFab || empty || unsupported || hasMac, isTrue);
    });
  });

  group('App UI: Navigation flow', () {
    testWidgets('switches across tabs and back to the dashboard', (
      tester,
    ) async {
      await pumpApp(tester);

      await switchTab(tester, 'About');
      expect(find.text('What this platform can do'), findsOneWidget);

      await switchTab(tester, 'Server');
      expect(
        find.text('RFCOMM server').evaluate().isNotEmpty ||
            find.text('Server mode not supported').evaluate().isNotEmpty,
        isTrue,
      );

      await switchTab(tester, 'Dashboard');
      final onDashboard =
          find.textContaining('Adapter').evaluate().isNotEmpty ||
          find.text('Bluetooth Classic unavailable').evaluate().isNotEmpty;
      expect(onDashboard, isTrue);
    });
  });

  group('App UI: Loading state', () {
    testWidgets('shows a spinner before the first data frame settles', (
      tester,
    ) async {
      await tester.pumpWidget(const BluetoothExampleApp());
      await tester.pump(); // one frame, controller.init() may be in flight
      final spinner = find
          .byType(CircularProgressIndicator)
          .evaluate()
          .isNotEmpty;
      final content = find.text('Bluetooth Classic').evaluate().isNotEmpty;
      expect(spinner || content, isTrue);

      await tester.pumpAndSettle();
      expect(find.text('Bluetooth Classic'), findsAtLeast(1));
    });
  });
}
