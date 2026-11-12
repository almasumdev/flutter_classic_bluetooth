// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';

import '../connect_flow.dart';
import '../controller.dart';
import '../widgets.dart';

class DiscoverPage extends StatelessWidget {
  const DiscoverPage({super.key, required this.controller});

  final BluetoothController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.caps.canDiscoverDevices) {
          return const EmptyState(
            icon: Icons.search_off,
            title: 'Discovery not supported',
            message:
                'This platform cannot scan for nearby devices '
                '(for example iOS, which is limited to MFi accessories).',
          );
        }
        if (!controller.isOn) {
          return const EmptyState(
            icon: Icons.bluetooth_disabled,
            title: 'Bluetooth is off',
            message: 'Turn the adapter on from the Dashboard to scan.',
          );
        }

        final devices = controller.discovered;
        return Scaffold(
          body: Column(
            children: [
              _ScanHeader(controller: controller),
              Expanded(
                child: devices.isEmpty
                    ? EmptyState(
                        icon: controller.scanning
                            ? Icons.bluetooth_searching
                            : Icons.radar,
                        title: controller.scanning
                            ? 'Scanning...'
                            : 'No devices yet',
                        message: controller.scanning
                            ? 'Make sure the target device is powered on and '
                                  'discoverable.'
                            : 'Tap Scan to look for nearby Bluetooth Classic '
                                  'devices.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: devices.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, indent: 76),
                        itemBuilder: (context, i) => _DiscoveredTile(
                          device: devices[i],
                          onConnect: () =>
                              connectTo(context, controller.bt, devices[i]),
                        ),
                      ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: controller.scanning
                ? controller.stopScan
                : controller.startScan,
            icon: Icon(controller.scanning ? Icons.stop : Icons.radar),
            label: Text(controller.scanning ? 'Stop' : 'Scan'),
          ),
        );
      },
    );
  }
}

class _ScanHeader extends StatelessWidget {
  const _ScanHeader({required this.controller});
  final BluetoothController controller;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      color: controller.scanning ? cs.primaryContainer : cs.surface,
      child: Column(
        children: [
          if (controller.scanning) const LinearProgressIndicator(minHeight: 3),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  controller.scanning
                      ? Icons.bluetooth_searching
                      : Icons.bluetooth,
                  color: controller.scanning ? cs.onPrimaryContainer : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    controller.scanning
                        ? 'Scanning for devices...'
                        : '${controller.discovered.length} device(s) found',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: controller.scanning ? cs.onPrimaryContainer : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscoveredTile extends StatelessWidget {
  const _DiscoveredTile({required this.device, required this.onConnect});

  final BtcDevice device;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: DeviceAvatar(device: device),
      title: Text(device.displayName),
      subtitle: Text(
        device.address,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (device.rssi != null) ...[
            Text(
              '${device.rssi} dBm',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(width: 8),
          ],
          SignalBars(rssi: device.rssi),
        ],
      ),
      onTap: onConnect,
    );
  }
}
