// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../controller.dart';
import '../widgets.dart';

class CapabilitiesPage extends StatelessWidget {
  const CapabilitiesPage({super.key, required this.controller});

  final BluetoothController controller;

  @override
  Widget build(BuildContext context) {
    final caps = controller.caps;
    final rows = <(String, bool)>[
      ('Discover devices', caps.canDiscoverDevices),
      ('Get paired devices', caps.canGetPairedDevices),
      ('Pair (bond)', caps.canBondDevices),
      ('Unpair (unbond)', caps.canUnbondDevices),
      ('Enable Bluetooth', caps.canEnableBluetooth),
      ('Disable Bluetooth', caps.canDisableBluetooth),
      ('Create RFCOMM server', caps.canCreateServer),
      ('Set discoverable', caps.canSetDiscoverable),
      ('Multiple connections', caps.supportsMultipleConnections),
      ('Secure connections', caps.supportsSecureConnection),
      ('Insecure connections', caps.supportsInsecureConnection),
      ('Requires MFi certification', caps.requiresMfiCertification),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionCard(
          title: 'What this platform can do',
          icon: Icons.fact_check_outlined,
          child: Column(
            children: [
              for (final row in rows) _CapRow(label: row.$1, on: row.$2),
            ],
          ),
        ),
        if (caps.platformNote != null) ...[
          const SizedBox(height: 16),
          SectionCard(
            title: 'Platform note',
            icon: Icons.info_outline,
            child: Text(
              caps.platformNote!,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Query these flags via getPlatformCapabilities() before calling a '
          'feature, so your UI only offers what works on the current OS.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _CapRow extends StatelessWidget {
  const _CapRow({required this.label, required this.on});

  final String label;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            on ? Icons.check_circle : Icons.remove_circle_outline,
            color: on ? cs.primary : cs.outline,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}
