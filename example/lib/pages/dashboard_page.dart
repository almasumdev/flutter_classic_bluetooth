// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../controller.dart';
import '../widgets.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.controller, this.onNavigate});

  final BluetoothController controller;

  /// Switches the app shell to the tab at the given index (Discover = 1,
  /// Paired = 2), so a quick action lands the user where its result appears.
  final void Function(int index)? onNavigate;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.supported) {
          return const EmptyState(
            icon: Icons.bluetooth_disabled,
            title: 'Bluetooth Classic unavailable',
            message: 'This device reports no Bluetooth Classic hardware.',
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _AdapterHero(controller: controller),
            const SizedBox(height: 16),
            _AdapterInfo(controller: controller),
            const SizedBox(height: 16),
            _QuickActions(controller: controller, onNavigate: onNavigate),
          ],
        );
      },
    );
  }
}

class _AdapterHero extends StatelessWidget {
  const _AdapterHero({required this.controller});
  final BluetoothController controller;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = adapterVisual(controller.adapterState, cs);
    final on = controller.isOn;
    final canToggle = on
        ? controller.caps.canDisableBluetooth
        : controller.caps.canEnableBluetooth;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: on
                ? [cs.primary, cs.primaryContainer]
                : [cs.surfaceContainerHighest, cs.surfaceContainerHigh],
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(v.icon, size: 36, color: on ? cs.onPrimary : v.color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Adapter ${v.label}',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: on ? cs.onPrimary : cs.onSurface,
                        ),
                      ),
                      Text(
                        controller.adapterName ?? 'Bluetooth Classic',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: on
                              ? cs.onPrimary.withValues(alpha: 0.85)
                              : cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: canToggle ? controller.toggleAdapter : null,
                icon: Icon(on ? Icons.bluetooth_disabled : Icons.bluetooth),
                label: Text(on ? 'Turn off' : 'Turn on'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdapterInfo extends StatelessWidget {
  const _AdapterInfo({required this.controller});
  final BluetoothController controller;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Adapter',
      icon: Icons.info_outline,
      child: Column(
        children: [
          KeyValueRow('Name', controller.adapterName ?? '-'),
          KeyValueRow('Address', controller.adapterAddress ?? '-', mono: true),
          KeyValueRow('State', controller.adapterState.name),
          KeyValueRow('Paired', '${controller.paired.length} device(s)'),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.controller, this.onNavigate});
  final BluetoothController controller;
  final void Function(int index)? onNavigate;

  @override
  Widget build(BuildContext context) {
    final caps = controller.caps;
    return SectionCard(
      title: 'Quick actions',
      icon: Icons.bolt,
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          if (caps.canDiscoverDevices)
            ActionChip(
              avatar: const Icon(Icons.radar, size: 18),
              label: const Text('Scan'),
              onPressed: controller.isOn
                  ? () {
                      onNavigate?.call(1); // jump to Discover
                      controller.startScan();
                    }
                  : null,
            ),
          if (caps.canGetPairedDevices)
            ActionChip(
              avatar: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh paired'),
              onPressed: controller.isOn
                  ? () {
                      onNavigate?.call(2); // jump to Paired
                      controller.refreshPaired();
                    }
                  : null,
            ),
          if (caps.canSetDiscoverable)
            ActionChip(
              avatar: const Icon(Icons.visibility, size: 18),
              label: const Text('Discoverable 120s'),
              onPressed: controller.isOn
                  ? () async {
                      final ok = await controller.setDiscoverable(120);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              ok
                                  ? 'Now discoverable for 120s'
                                  : 'Could not set discoverable',
                            ),
                          ),
                        );
                      }
                    }
                  : null,
            ),
        ],
      ),
    );
  }
}
