import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../btc_frame_splitter.dart';
import 'btc_enums.dart';
import 'btc_exceptions.dart';
import 'btc_stream_sink.dart';

/// An active RFCOMM connection to a remote Bluetooth device.
///
/// Provides a byte stream [input] for reading data and a [output] sink
/// for writing data. Multiple connections can be active simultaneously,
/// each identified by a unique [id].
///
/// ## Usage
/// ```dart
/// final connection = await bluetooth.connect(
///   address: 'AA:BB:CC:DD:EE:FF',
///   uuid: '00001101-0000-1000-8000-00805F9B34FB',
/// );
/// connection.input.listen((data) {
///   print('Received: $data');
/// });
/// await connection.output.add(Uint8List.fromList([0x01, 0x02]));
/// await connection.finish(); // graceful disconnect
/// ```
///
/// ## Lifecycle
/// - [finish] waits for pending writes then disconnects.
/// - [close] disconnects immediately, discarding pending writes.
/// - [dispose] cleans up all resources. Always call this when done.
///
/// {@category Models}
class BtcConnection {
  /// Unique identifier for this connection assigned by the native side.
  final int id;

  /// The address of the connected remote device.
  final String address;

  final MethodChannel _methodChannel;
  late final EventChannel _dataChannel;
  late final EventChannel _stateChannel;

  late final Stream<Uint8List> _inputStream;
  late final BtcStreamSink _outputSink;
  late final Stream<BtcConnectionState> _nativeStateStream;

  /// Merges native connection-state events with local lifecycle transitions
  /// (e.g. [BtcConnectionState.disconnecting] emitted by [finish]/[close]).
  final StreamController<BtcConnectionState> _stateController =
      StreamController<BtcConnectionState>.broadcast();

  StreamSubscription<BtcConnectionState>? _stateSubscription;
  BtcConnectionState _state = BtcConnectionState.connected;

  /// Creates a [BtcConnection] wrapping the native connection [id].
  ///
  /// This constructor is intended to be called by the method channel
  /// implementation, not directly by users.
  BtcConnection({
    required this.id,
    required this.address,
    required MethodChannel methodChannel,
  }) : _methodChannel = methodChannel {
    _dataChannel = EventChannel('flutter_classic_bluetooth/connection/$id');
    _stateChannel = EventChannel(
      'flutter_classic_bluetooth/connection_state/$id',
    );

    _inputStream = _dataChannel.receiveBroadcastStream().map(
      (event) => event as Uint8List,
    );

    _outputSink = BtcStreamSink(
      connectionId: id,
      methodChannel: _methodChannel,
    );

    _nativeStateStream = _stateChannel.receiveBroadcastStream().map((event) {
      return BtcConnectionState.values.firstWhere(
        (e) => e.name == event,
        orElse: () => BtcConnectionState.disconnected,
      );
    });

    // Forward native state events into the merged controller.
    _stateSubscription = _nativeStateStream.listen(_setState);
  }

  void _setState(BtcConnectionState state) {
    _state = state;
    if (!_stateController.isClosed) _stateController.add(state);
  }

  /// Stream of incoming bytes from the remote device.
  Stream<Uint8List> get input => _inputStream;

  /// Sink for writing bytes to the remote device.
  ///
  /// Writes are queued and delivered in order. Use [BtcStreamSink.add]
  /// to write data.
  BtcStreamSink get output => _outputSink;

  /// Stream of connection state changes.
  ///
  /// Emits [BtcConnectionState.disconnecting] when [finish]/[close] begins and
  /// [BtcConnectionState.disconnected] once the link is torn down, in addition
  /// to any native-originated transitions (e.g. a remote-initiated drop).
  Stream<BtcConnectionState> get stateStream => _stateController.stream;

  /// The current connection state.
  BtcConnectionState get state => _state;

  /// Whether this connection is currently active.
  bool get isConnected => _state == BtcConnectionState.connected;

  /// Sends [command] (terminated by [newline]) and completes with the first
  /// response line (or the first line for which [where] returns `true`),
  /// decoded with [encoding].
  ///
  /// Lines are read via [input] with `.lines()` framing, so responses split
  /// across RFCOMM chunks are reassembled. Ideal for AT-command modules
  /// (HC-05, ESP-AT) and other request/response line protocols.
  ///
  /// ```dart
  /// final version = await connection.sendAndReceive('AT+GMR');
  /// final ok = await connection.sendAndReceive('AT', where: (l) => l == 'OK');
  /// ```
  ///
  /// Throws [BtcTimeoutException] if no matching line arrives within [timeout].
  Future<String> sendAndReceive(
    String command, {
    Duration timeout = const Duration(seconds: 5),
    bool Function(String line)? where,
    String newline = '\r\n',
    Encoding encoding = utf8,
  }) async {
    final completer = Completer<String>();
    // Subscribe before writing so a fast response is never missed.
    final sub = input
        .lines(encoding: encoding)
        .listen(
          (line) {
            if (!completer.isCompleted && (where == null || where(line))) {
              completer.complete(line);
            }
          },
          onError: (Object e) {
            if (!completer.isCompleted) completer.completeError(e);
          },
        );
    try {
      await _outputSink.writeString('$command$newline', encoding: encoding);
      return await completer.future.timeout(
        timeout,
        onTimeout: () => throw BtcTimeoutException(
          message:
              'No response to "$command" within ${timeout.inMilliseconds}ms',
          timeoutMs: timeout.inMilliseconds,
        ),
      );
    } finally {
      await sub.cancel();
    }
  }

  /// Reads the live signal strength (RSSI, in dBm) of this open connection.
  ///
  /// Returns a negative dBm value (e.g. `-42`; closer to `0` is stronger), or
  /// `null` when the platform supports RSSI but has no fresh sample this instant.
  ///
  /// Supported on **macOS only** (via `IOBluetoothDevice`). Android, iOS,
  /// Windows and Linux have no public Bluetooth Classic API for connection RSSI
  /// and throw [BtcUnsupportedException]. Check
  /// `BtcPlatformCapabilities.canReadConnectionRssi` before calling. (Note:
  /// discovery-time RSSI is always available separately on `BtcDevice.rssi`.)
  Future<int?> readRssi() async {
    try {
      return await _methodChannel.invokeMethod<int>('getConnectionRssi', {
        'id': id,
      });
    } on MissingPluginException {
      throw const BtcUnsupportedException(
        feature: 'getConnectionRssi',
        platform: 'this platform',
      );
    } on PlatformException catch (e) {
      if (e.code == 'unsupported') {
        throw BtcUnsupportedException(
          feature: e.details?['feature'] as String? ?? 'getConnectionRssi',
          platform: e.details?['platform'] as String? ?? 'unknown',
          reason: e.message,
        );
      }
      throw BtcException(e.message ?? 'Failed to read RSSI', code: e.code);
    }
  }

  /// Gracefully disconnects: waits for all pending writes to complete,
  /// then closes the connection.
  Future<void> finish() async {
    _setState(BtcConnectionState.disconnecting);
    await _outputSink.close();
    await _methodChannel.invokeMethod('disconnect', {'id': id});
    _setState(BtcConnectionState.disconnected);
    await _stateSubscription?.cancel();
    _stateSubscription = null;
  }

  /// Immediately disconnects, discarding any pending writes.
  Future<void> close() async {
    _setState(BtcConnectionState.disconnecting);
    _outputSink.cancel();
    await _methodChannel.invokeMethod('disconnect', {'id': id});
    _setState(BtcConnectionState.disconnected);
    await _stateSubscription?.cancel();
    _stateSubscription = null;
  }

  /// Releases all resources associated with this connection.
  ///
  /// Always call [dispose] when you are done with a connection.
  /// After calling this, the connection object should not be reused.
  void dispose() {
    _stateSubscription?.cancel();
    _stateSubscription = null;
    _outputSink.cancel();
    if (!_stateController.isClosed) _stateController.close();
  }
}
