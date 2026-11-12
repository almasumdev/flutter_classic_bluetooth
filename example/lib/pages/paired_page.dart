// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';

import '../connect_flow.dart';
import '../controller.dart';
import '../widgets.dart';

class PairedPage extends StatelessWidget {
  const PairedPage({super.key, required this.controller});

  final BluetoothController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.caps.canGetPairedDevices) {
          return const EmptyState(
            icon: Icons.devices_other,
            title: 'Paired list not available',
            message: 'This platform cannot enumerate paired devices.',
          );
        }

        final devices = controller.paired;
        return Scaffold(
          body: RefreshIndicator(
            onRefresh: controller.refreshPaired,
            child: controller.loadingPaired && devices.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : devices.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 120),
                      EmptyState(
                        icon: Icons.link_off,
                        title: 'No paired devices',
                        message:
                            'Pair a device from your system settings '
                            'or the Discover tab, then pull to refresh.',
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: devices.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 76),
                    itemBuilder: (context, i) =>
                        _PairedTile(controller: controller, device: devices[i]),
                  ),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: controller.refreshPaired,
            child: const Icon(Icons.refresh),
          ),
        );
      },
    );
  }
}

class _PairedTile extends StatelessWidget {
  const _PairedTile({required this.controller, required this.device});

  final BluetoothController controller;
  final BtcDevice device;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bond = bondVisual(device.bondState, cs);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: DeviceAvatar(device: device),
      title: Text(device.displayName),
      subtitle: Text(
        device.address,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) async {
          switch (value) {
            case 'connect':
              await connectTo(context, controller.bt, device);
            case 'unbond':
              await controller.unbond(device);
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'connect',
            child: ListTile(
              leading: Icon(Icons.bluetooth_connected),
              title: Text('Connect'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          if (controller.caps.canUnbondDevices)
            const PopupMenuItem(
              value: 'unbond',
              child: ListTile(
                leading: Icon(Icons.link_off),
                title: Text('Unpair'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
        ],
      ),
      onTap: () => connectTo(context, controller.bt, device),
      onLongPress: () => showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(device.displayName),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KeyValueRow('Address', device.address, mono: true),
              KeyValueRow('Bond', bond.label),
              KeyValueRow('Type', device.type.name),
              if (device.uuids.isNotEmpty)
                KeyValueRow('Services', '${device.uuids.length} UUID(s)'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
