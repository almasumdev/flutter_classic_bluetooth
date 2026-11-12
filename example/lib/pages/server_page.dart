import 'dart:async';

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';

import '../controller.dart';
import '../pages/connection_page.dart';
import '../widgets.dart';

class ServerPage extends StatefulWidget {
  const ServerPage({super.key, required this.controller});

  final BluetoothController controller;

  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> {
  BtcServerSocket? _server;
  StreamSubscription<BtcConnection>? _sub;
  final _clients = <BtcConnection>[];
  bool _busy = false;
  String? _error;

  final _name = TextEditingController(text: 'Flutter SPP');
  final _uuid = TextEditingController(text: BtcUuid.spp);
  bool _secure = true;

  bool get _running => _server != null;

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final server = await widget.controller.bt.startServer(
        uuid: _uuid.text.trim(),
        serviceName: _name.text.trim().isEmpty ? 'Flutter SPP' : _name.text,
        secure: _secure,
      );
      _sub = server.connections.listen((client) {
        if (!mounted) return;
        setState(() => _clients.insert(0, client));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Client connected: ${client.address}')),
        );
      });
      setState(() => _server = server);
    } on BtcException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    await _sub?.cancel();
    _sub = null;
    await _server?.close();
    if (mounted) setState(() => _server = null);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _server?.close();
    _name.dispose();
    _uuid.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (!controller.caps.canCreateServer) {
      return const EmptyState(
        icon: Icons.dns_outlined,
        title: 'Server mode not supported',
        message:
            'This platform cannot host an RFCOMM server '
            '(for example iOS).',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionCard(
          title: 'RFCOMM server',
          icon: Icons.dns,
          trailing: StatusPill(
            label: _running ? 'Listening' : 'Stopped',
            color: _running
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline,
            icon: _running ? Icons.wifi_tethering : Icons.stop_circle_outlined,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                enabled: !_running,
                decoration: const InputDecoration(
                  labelText: 'Service name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _uuid,
                enabled: !_running,
                decoration: const InputDecoration(
                  labelText: 'Service UUID',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.tag),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _secure,
                onChanged: _running ? null : (v) => setState(() => _secure = v),
                title: const Text('Secure connection'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: _running
                    ? OutlinedButton.icon(
                        onPressed: _busy ? null : _stop,
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop server'),
                      )
                    : FilledButton.icon(
                        onPressed: _busy ? null : _start,
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.play_arrow),
                        label: const Text('Start server'),
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Connected clients (${_clients.length})',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        if (_clients.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: EmptyState(
              icon: Icons.group_outlined,
              title: 'No clients yet',
              message:
                  'Start the server, then connect to it from another '
                  'device. Clients appear here in real time.',
            ),
          )
        else
          ..._clients.map(
            (c) => Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.phone_android)),
                title: Text(c.address),
                subtitle: Text('Connection #${c.id}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  setState(() => _clients.remove(c));
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ConnectionPage(
                        connection: c,
                        title: 'Client ${c.address}',
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
