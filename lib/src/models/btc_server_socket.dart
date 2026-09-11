import 'dart:async';

import 'package:flutter/services.dart';

import 'btc_connection.dart';

/// A server socket that listens for incoming Bluetooth RFCOMM connections.
///
/// Creates an RFCOMM server on the specified UUID and waits for remote
/// devices to connect. Each incoming connection is delivered as a
/// [BtcConnection] through the [connections] stream.
///
/// ## Usage
/// ```dart
/// final server = await bluetooth.startServer(
///   uuid: '00001101-0000-1000-8000-00805F9B34FB',
///   serviceName: 'MyService',
/// );
/// server.connections.listen((connection) {
///   print('Client connected: ${connection.address}');
///   connection.input.listen((data) => print('Data: $data'));
/// });
/// // ...later
/// await server.close();
/// ```
///
/// {@category Models}
///
/// ## Platform Support
/// | Platform | Supported |
/// |----------|-----------|
/// | Android | Yes |
/// | Windows | Yes |
/// | macOS | Yes |
/// | Linux | Yes |
/// | iOS | No (no server mode) |
class BtcServerSocket {
  /// Unique identifier for this server assigned by the native side.
  final int id;

  /// The UUID used for the RFCOMM service record.
  final String uuid;

  /// The human-readable service name.
  final String serviceName;

  final MethodChannel _methodChannel;
  late final EventChannel _serverChannel;
  late final Stream<BtcConnection> _connectionsStream;

  /// Creates a [BtcServerSocket] wrapping the native server [id].
  ///
  /// This constructor is intended to be called by the method channel
  /// implementation, not directly by users.
  BtcServerSocket({
    required this.id,
    required this.uuid,
    required this.serviceName,
    required this._methodChannel,
  }) {
    _serverChannel = EventChannel('flutter_classic_bluetooth/server/$id');

    _connectionsStream = _serverChannel.receiveBroadcastStream().map((event) {
      final map = Map<dynamic, dynamic>.from(event as Map);
      return BtcConnection(
        id: map['id'] as int,
        address: map['address'] as String,
        methodChannel: _methodChannel,
      );
    });
  }

  /// Stream of incoming connections from remote devices.
  Stream<BtcConnection> get connections => _connectionsStream;

  /// Stops the server and releases the RFCOMM channel.
  ///
  /// No more incoming connections will be accepted after this.
  /// Existing connections are **not** affected.
  Future<void> close() async {
    await _methodChannel.invokeMethod('stopServer', {'id': id});
  }
}
