import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

/// A write sink for an active Bluetooth connection.
///
/// Writes are queued and delivered in order using chained futures,
/// ensuring that data is sent sequentially even if [add] is called
/// multiple times without awaiting.
///
/// ```dart
/// final sink = connection.output;
/// await sink.add(Uint8List.fromList([0x01, 0x02]));
/// await sink.add(utf8.encode('Hello'));
/// await sink.close(); // waits for all pending writes
/// ```
///
/// {@category Models}
class BtcStreamSink {
  /// The ID of the connection this sink writes to.
  final int connectionId;
  final MethodChannel _methodChannel;
  Future<void> _lastWrite = Future.value();
  bool _closed = false;

  /// Creates a [BtcStreamSink] for the given [connectionId].
  BtcStreamSink({
    required this.connectionId,
    required MethodChannel methodChannel,
  }) : _methodChannel = methodChannel;

  /// Whether this sink has been closed.
  bool get isClosed => _closed;

  /// Queues [data] to be written to the remote device.
  ///
  /// Writes are chained so they execute in the order they are added.
  /// The returned future completes when this particular write finishes.
  /// Throws [StateError] if the sink has been closed.
  Future<void> add(Uint8List data) {
    if (_closed) {
      throw StateError('Cannot write to a closed BtcStreamSink');
    }

    _lastWrite = _lastWrite.then((_) {
      return _methodChannel.invokeMethod('write', {
        'id': connectionId,
        'data': data,
      });
    });

    return _lastWrite;
  }

  /// Queues raw [bytes] to be written, accepting any `List<int>`.
  ///
  /// Convenience wrapper around [add] that copies [bytes] into a [Uint8List].
  Future<void> writeBytes(List<int> bytes) =>
      add(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));

  /// Encodes [text] (UTF-8 by default) and queues it to be written.
  Future<void> writeString(String text, {Encoding encoding = utf8}) =>
      add(Uint8List.fromList(encoding.encode(text)));

  /// Writes [text] followed by [newline] (CRLF by default), the common shape
  /// for line-based serial protocols (AT commands, etc.).
  Future<void> writeLine(
    String text, {
    String newline = '\r\n',
    Encoding encoding = utf8,
  }) => writeString('$text$newline', encoding: encoding);

  /// Pipes every chunk of [stream] to the remote device, in order.
  ///
  /// Completes when [stream] is done and all of its chunks have been written.
  /// Throws [StateError] if the sink is (or becomes) closed.
  Future<void> addStream(Stream<Uint8List> stream) async {
    await for (final chunk in stream) {
      await add(chunk);
    }
  }

  /// Resolves when all writes queued so far have completed.
  ///
  /// Unlike [close], this does not mark the sink as closed. More data can be
  /// queued afterwards.
  Future<void> get allSent => _lastWrite;

  /// Waits for all pending writes to complete, then marks this sink as closed.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _lastWrite;
  }

  /// Immediately marks the sink as closed without waiting for pending writes.
  void cancel() {
    _closed = true;
  }
}
