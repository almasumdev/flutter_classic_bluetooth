import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'btc_uuid.dart';
import 'models/btc_connection.dart';
import 'models/btc_enums.dart';
import 'models/btc_exceptions.dart';
import 'models/btc_reconnect_policy.dart';

/// A self-healing RFCOMM connection that transparently reconnects when the link
/// drops, using the exponential backoff described by its [policy].
///
/// Unlike a raw [BtcConnection] (which is replaced on every drop), this
/// object's [input] and [state] streams are **stable**: subscribe once and keep
/// receiving data and status across reconnects. Create one via
/// [FlutterClassicBluetooth.connectWithReconnect].
///
/// ```dart
/// final link = bluetooth.connectWithReconnect(address: 'AA:BB:CC:DD:EE:FF');
/// link.state.listen((s) => print('Link: ${s.name}'));
/// link.input.listen((bytes) => print('RX ${bytes.length} bytes'));
/// await link.sendString('PING\r\n'); // throws if currently reconnecting
/// // ...later
/// await link.close(); // stop reconnecting and release everything
/// ```
///
/// {@category Models}
class BtcReconnectingConnection {
  /// Creates a reconnecting connection driven by [connector].
  ///
  /// [connector] is invoked for every (re)connect attempt and must return a
  /// fresh [BtcConnection]. Call [start] to begin, or just use
  /// [FlutterClassicBluetooth.connectWithReconnect], which wires the connector
  /// and starts it for you.
  BtcReconnectingConnection({
    required this.address,
    required this._connector,
    this.uuid = BtcUuid.spp,
    this.secure = true,
    this.policy = const BtcReconnectPolicy(),
  });

  /// The remote device address this link targets.
  final String address;

  /// The RFCOMM service UUID used for each connect attempt.
  final String uuid;

  /// Whether each connect attempt uses authenticated/encrypted RFCOMM.
  final bool secure;

  /// The backoff/retry policy.
  final BtcReconnectPolicy policy;

  final Future<BtcConnection> Function() _connector;

  final StreamController<Uint8List> _input =
      StreamController<Uint8List>.broadcast();
  final StreamController<BtcReconnectState> _stateCtl =
      StreamController<BtcReconnectState>.broadcast();

  BtcConnection? _current;
  StreamSubscription<Uint8List>? _dataSub;
  StreamSubscription<BtcConnectionState>? _stateSub;
  Timer? _retryTimer;
  int _attempt = 0;
  Object? _lastError;
  bool _closed = false;
  bool _retryPending = false;
  BtcReconnectState _state = BtcReconnectState.connecting;

  /// Incoming bytes from the remote device, stable across reconnects.
  Stream<Uint8List> get input => _input.stream;

  /// High-level link-state changes (connecting → connected → reconnecting → ...).
  Stream<BtcReconnectState> get state => _stateCtl.stream;

  /// The current link state.
  BtcReconnectState get currentState => _state;

  /// The underlying live connection, or `null` while reconnecting/closed.
  BtcConnection? get connection => _current;

  /// Whether a connection is established right now.
  bool get isConnected => _state == BtcReconnectState.connected;

  /// Consecutive failed reconnect attempts since the last successful connect.
  int get attempts => _attempt;

  /// The error from the most recent failed connect attempt, or `null`.
  Object? get lastError => _lastError;

  /// Begins connecting. Has no effect if already started or [close]d.
  void start() {
    if (_closed) return;
    _attempt = 0;
    unawaited(_connect());
  }

  Future<void> _connect() async {
    if (_closed) return;
    _setState(
      _attempt == 0
          ? BtcReconnectState.connecting
          : BtcReconnectState.reconnecting,
    );

    BtcConnection conn;
    try {
      final future = _connector();
      final timeout = policy.connectTimeout;
      conn = await (timeout == null
          ? future
          : future.timeout(
              timeout,
              onTimeout: () => throw BtcTimeoutException(
                message: 'Reconnect to $address timed out',
                timeoutMs: timeout.inMilliseconds,
              ),
            ));
    } catch (e) {
      _lastError = e;
      _onDropped();
      return;
    }

    // A close() may have landed while the attempt was in flight.
    if (_closed) {
      await conn.close().catchError((_) {});
      conn.dispose();
      return;
    }

    _current = conn;
    _attempt = 0;
    _lastError = null;
    _retryPending = false;
    _setState(BtcReconnectState.connected);

    _dataSub = conn.input.listen(
      _input.add,
      onError: _input.addError,
      onDone: _onDropped,
    );
    _stateSub = conn.stateStream.listen((s) {
      if (s == BtcConnectionState.disconnected) _onDropped();
    });
  }

  void _onDropped() {
    if (_closed || _retryPending) return;
    _retryPending = true;
    _teardownCurrent();
    _attempt++;

    final max = policy.maxAttempts;
    if (max != null && _attempt > max) {
      _setState(BtcReconnectState.failed);
      return;
    }

    _setState(BtcReconnectState.reconnecting);
    _retryTimer = Timer(policy.backoffForAttempt(_attempt), () {
      _retryPending = false;
      unawaited(_connect());
    });
  }

  void _teardownCurrent() {
    _dataSub?.cancel();
    _dataSub = null;
    _stateSub?.cancel();
    _stateSub = null;
    _current?.dispose();
    _current = null;
  }

  /// Sends [data] over the current connection.
  ///
  /// Throws [BtcConnectionException] if the link is not connected right now
  /// (e.g. mid-reconnect). Check [isConnected] or watch [state] first.
  Future<void> send(Uint8List data) {
    final conn = _current;
    if (conn == null || _state != BtcReconnectState.connected) {
      throw const BtcConnectionException('Not connected');
    }
    return conn.output.add(data);
  }

  /// Encodes [text] (UTF-8 by default) and sends it. See [send].
  Future<void> sendString(String text, {Encoding encoding = utf8}) =>
      send(Uint8List.fromList(encoding.encode(text)));

  /// Sends [text] followed by [newline] (CRLF by default). See [send].
  Future<void> sendLine(
    String text, {
    String newline = '\r\n',
    Encoding encoding = utf8,
  }) => sendString('$text$newline', encoding: encoding);

  /// Sends [command] over the current connection and awaits its response line.
  ///
  /// Delegates to [BtcConnection.sendAndReceive] on the live connection. Throws
  /// [BtcConnectionException] if the link is reconnecting, or
  /// [BtcTimeoutException] if no response arrives within [timeout]. If the link
  /// drops mid-transaction the call fails and can be retried once reconnected.
  Future<String> sendAndReceive(
    String command, {
    Duration timeout = const Duration(seconds: 5),
    bool Function(String line)? where,
    String newline = '\r\n',
    Encoding encoding = utf8,
  }) {
    final conn = _current;
    if (conn == null || _state != BtcReconnectState.connected) {
      throw const BtcConnectionException('Not connected');
    }
    return conn.sendAndReceive(
      command,
      timeout: timeout,
      where: where,
      newline: newline,
      encoding: encoding,
    );
  }

  /// Stops reconnecting, disconnects, and releases all resources.
  ///
  /// After this the object is finished. Its [input] and [state] streams close.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _retryTimer?.cancel();
    _dataSub?.cancel();
    _dataSub = null;
    _stateSub?.cancel();
    _stateSub = null;
    final conn = _current;
    _current = null;
    if (conn != null) {
      await conn.finish().catchError((_) {});
      conn.dispose();
    }
    _setState(BtcReconnectState.closed);
    await _input.close();
    await _stateCtl.close();
  }

  void _setState(BtcReconnectState s) {
    _state = s;
    if (!_stateCtl.isClosed) _stateCtl.add(s);
  }
}
