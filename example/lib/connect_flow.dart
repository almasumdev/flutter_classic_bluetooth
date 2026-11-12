// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';

import 'pages/connection_page.dart';

/// Opens a bottom sheet to configure and start an outbound RFCOMM connection to
/// [device]. On success it pushes the live [ConnectionPage] terminal.
Future<void> connectTo(
  BuildContext context,
  FlutterClassicBluetooth bt,
  BtcDevice device,
) async {
  final result = await showModalBottomSheet<_ConnectConfig>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ConnectSheet(device: device),
  );
  if (result == null || !context.mounted) return;

  // Drive the connect attempt behind a progress dialog.
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    final conn = await bt.connect(
      address: device.address,
      uuid: result.uuid,
      secure: result.secure,
      timeout: const Duration(seconds: 15),
    );
    navigator.pop(); // dismiss progress
    await navigator.push(
      MaterialPageRoute(
        builder: (_) =>
            ConnectionPage(connection: conn, title: device.displayName),
      ),
    );
  } on BtcException catch (e) {
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (e) {
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text('Connect failed: $e')));
  }
}

class _ConnectConfig {
  _ConnectConfig(this.uuid, this.secure);
  final String uuid;
  final bool secure;
}

class _ConnectSheet extends StatefulWidget {
  const _ConnectSheet({required this.device});
  final BtcDevice device;

  @override
  State<_ConnectSheet> createState() => _ConnectSheetState();
}

class _ConnectSheetState extends State<_ConnectSheet> {
  late final TextEditingController _uuid = TextEditingController(
    text: widget.device.uuids.isNotEmpty
        ? widget.device.uuids.first
        : BtcUuid.spp,
  );
  bool _secure = true;

  @override
  void dispose() {
    _uuid.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Connect', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            '${widget.device.displayName} · ${widget.device.address}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _uuid,
            decoration: const InputDecoration(
              labelText: 'Service UUID',
              helperText: 'SPP is the default for serial devices',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.tag),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _secure,
            onChanged: (v) => setState(() => _secure = v),
            title: const Text('Secure (authenticated + encrypted)'),
            subtitle: const Text('Turn off for HC-05/06 modules without a PIN'),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                final uuid = _uuid.text.trim();
                if (uuid.isEmpty) return;
                Navigator.of(context).pop(_ConnectConfig(uuid, _secure));
              },
              icon: const Icon(Icons.bluetooth_connected),
              label: const Text('Connect'),
            ),
          ),
        ],
      ),
    );
  }
}
