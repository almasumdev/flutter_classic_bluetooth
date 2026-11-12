import 'dart:async';
import 'dart:convert';

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';

import '../widgets.dart';

/// A live RFCOMM "serial terminal": shows sent/received frames in real time,
/// lets you type and send text, and reflects connection-state changes as they
/// happen. This is the screen a user of the plugin actually interacts with.
class ConnectionPage extends StatefulWidget {
  const ConnectionPage({super.key, required this.connection, this.title});

  final BtcConnection connection;
  final String? title;

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

enum _Dir { sent, received, system }

class _Frame {
  _Frame(this.dir, this.bytes, this.at);
  final _Dir dir;
  final Uint8List bytes;
  final DateTime at;
}

class _ConnectionPageState extends State<ConnectionPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _frames = <_Frame>[];

  StreamSubscription<dynamic>? _dataSub;
  StreamSubscription<BtcConnectionState>? _stateSub;

  BtcConnectionState _state = BtcConnectionState.connected;
  bool _hex = false;
  bool _lineMode = false;
  bool _appendNewline = true;
  int _rx = 0;
  int _tx = 0;

  @override
  void initState() {
    super.initState();
    _subscribe();
    _stateSub = widget.connection.stateStream.listen((s) {
      if (!mounted) return;
      setState(() => _state = s);
    });
  }

  /// (Re)subscribes to the input stream in the current mode. In line mode we
  /// use `input.lines()` so each complete, delimiter-terminated line becomes one
  /// received frame; otherwise raw chunks are shown as they arrive.
  void _subscribe() {
    _dataSub?.cancel();
    void onError(Object _) => _system('Input stream error');
    void onDone() => _system('Remote closed the stream');
    if (_lineMode) {
      _dataSub = widget.connection.input.lines().listen(
        (line) => _add(_Dir.received, Uint8List.fromList(utf8.encode(line))),
        onError: onError,
        onDone: onDone,
      );
    } else {
      _dataSub = widget.connection.input.listen(
        (data) => _add(_Dir.received, data),
        onError: onError,
        onDone: onDone,
      );
    }
  }

  void _add(_Dir dir, Uint8List bytes) {
    if (!mounted) return;
    setState(() {
      _frames.add(_Frame(dir, bytes, DateTime.now()));
      if (dir == _Dir.received) _rx += bytes.length;
      if (dir == _Dir.sent) _tx += bytes.length;
    });
    _autoScroll();
  }

  void _system(String text) {
    if (!mounted) return;
    setState(() {
      _frames.add(
        _Frame(
          _Dir.system,
          Uint8List.fromList(utf8.encode(text)),
          DateTime.now(),
        ),
      );
    });
    _autoScroll();
  }

  void _autoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.isEmpty || _state != BtcConnectionState.connected) return;
    final payload = _appendNewline ? '$text\r\n' : text;
    final bytes = Uint8List.fromList(utf8.encode(payload));
    try {
      await widget.connection.output.writeBytes(bytes);
      _add(_Dir.sent, bytes);
      _input.clear();
    } catch (e) {
      _system('Send failed: $e');
    }
  }

  Future<void> _disconnect() async {
    try {
      await widget.connection.finish();
    } catch (_) {
      // Already gone.
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    _stateSub?.cancel();
    _input.dispose();
    _scroll.dispose();
    widget.connection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = connectionVisual(_state, cs);
    final connected = _state == BtcConnectionState.connected;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title ?? widget.connection.address),
            Text(
              widget.connection.address,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: StatusPill(label: v.label, color: v.color, icon: v.icon),
            ),
          ),
          IconButton(
            tooltip: _lineMode ? 'Raw chunks' : 'Split into lines',
            icon: Icon(_lineMode ? Icons.notes : Icons.wrap_text),
            onPressed: () => setState(() {
              _lineMode = !_lineMode;
              _subscribe();
            }),
          ),
          IconButton(
            tooltip: _hex ? 'Show as text' : 'Show as hex',
            icon: Icon(_hex ? Icons.text_fields : Icons.data_array),
            onPressed: () => setState(() => _hex = !_hex),
          ),
        ],
      ),
      body: Column(
        children: [
          _MetaBar(rx: _rx, tx: _tx, frames: _frames.length),
          Expanded(
            child: _frames.isEmpty
                ? const EmptyState(
                    icon: Icons.terminal,
                    title: 'No data yet',
                    message:
                        'Sent and received bytes will appear here in '
                        'real time.',
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: _frames.length,
                    itemBuilder: (_, i) =>
                        _FrameBubble(frame: _frames[i], hex: _hex),
                  ),
          ),
          SafeArea(
            top: false,
            child: _Composer(
              controller: _input,
              enabled: connected,
              appendNewline: _appendNewline,
              onToggleNewline: (v) => setState(() => _appendNewline = v),
              onSend: _send,
              onDisconnect: _disconnect,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaBar extends StatelessWidget {
  const _MetaBar({required this.rx, required this.tx, required this.frames});

  final int rx;
  final int tx;
  final int frames;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: cs.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _stat(context, Icons.south, '$rx B', cs.primary, 'received'),
          const SizedBox(width: 20),
          _stat(context, Icons.north, '$tx B', cs.tertiary, 'sent'),
          const Spacer(),
          Text(
            '$frames frames',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ),
    );
  }

  Widget _stat(
    BuildContext context,
    IconData icon,
    String value,
    Color color,
    String tip,
  ) {
    return Tooltip(
      message: tip,
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(value, style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
  }
}

class _FrameBubble extends StatelessWidget {
  const _FrameBubble({required this.frame, required this.hex});

  final _Frame frame;
  final bool hex;

  String _format(Uint8List b) {
    if (hex) {
      return b
          .map((x) => x.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(' ');
    }
    return utf8.decode(b, allowMalformed: true);
  }

  String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (frame.dir == _Dir.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Text(
            _format(frame.bytes),
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }

    final sent = frame.dir == _Dir.sent;
    final bg = sent ? cs.primaryContainer : cs.surfaceContainerHighest;
    final fg = sent ? cs.onPrimaryContainer : cs.onSurface;

    return Align(
      alignment: sent ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: sent
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            SelectableText(
              _format(frame.bytes),
              style: TextStyle(
                color: fg,
                fontFamily: hex ? 'monospace' : null,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${_time(frame.at)} · ${frame.bytes.length} B',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: fg.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.appendNewline,
    required this.onToggleNewline,
    required this.onSend,
    required this.onDisconnect,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool appendNewline;
  final ValueChanged<bool> onToggleNewline;
  final VoidCallback onSend;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  inputFormatters: [LengthLimitingTextInputFormatter(512)],
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: enabled ? 'Type a message...' : 'Disconnected',
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: enabled ? onSend : null,
                icon: const Icon(Icons.send),
              ),
            ],
          ),
          Row(
            children: [
              Switch(value: appendNewline, onChanged: onToggleNewline),
              const Text('Append CR/LF'),
              const Spacer(),
              TextButton.icon(
                onPressed: onDisconnect,
                icon: const Icon(Icons.link_off),
                label: const Text('Disconnect'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
