import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

/// Splits a byte stream into frames separated by a [delimiter], buffering across
/// chunk boundaries so a frame may span several reads. The delimiter is stripped
/// from the emitted frames.
///
/// RFCOMM (like any stream transport) does not preserve message boundaries. A
/// single `input` event may contain part of a line, several lines, or a line
/// split mid-way. This transformer reassembles delimiter-terminated frames.
///
/// ```dart
/// connection.input
///     .transform(const BtcFrameSplitter()) // default delimiter: '\n'
///     .listen((frame) => print('line: ${utf8.decode(frame)}'));
/// ```
///
/// A trailing, un-terminated remainder is **not** emitted. Framing waits for
/// the delimiter. If [maxFrameLength] is set and the buffer grows past it before
/// a delimiter arrives, the stream emits a [StateError] and drops the buffer
/// (a guard against a missing delimiter growing memory without bound).
///
/// {@category Models}
class BtcFrameSplitter extends StreamTransformerBase<Uint8List, Uint8List> {
  /// Creates a splitter that breaks input on [delimiter] (default: `\n`).
  const BtcFrameSplitter({this.delimiter = const [0x0A], this.maxFrameLength});

  /// The byte sequence that separates frames.
  final List<int> delimiter;

  /// Optional cap on the buffered (un-terminated) bytes before erroring.
  final int? maxFrameLength;

  @override
  Stream<Uint8List> bind(Stream<Uint8List> stream) {
    final buffer = <int>[];
    StreamSubscription<Uint8List>? sub;
    late StreamController<Uint8List> out;

    void onData(Uint8List chunk) {
      buffer.addAll(chunk);
      var start = 0;
      var idx = _indexOf(buffer, delimiter, start);
      while (idx >= 0) {
        out.add(Uint8List.fromList(buffer.sublist(start, idx)));
        start = idx + delimiter.length;
        idx = _indexOf(buffer, delimiter, start);
      }
      if (start > 0) buffer.removeRange(0, start);
      if (maxFrameLength != null && buffer.length > maxFrameLength!) {
        buffer.clear();
        out.addError(
          StateError('Frame exceeded maxFrameLength ($maxFrameLength bytes)'),
        );
      }
    }

    out = StreamController<Uint8List>(
      onListen: () {
        sub = stream.listen(
          onData,
          onError: out.addError,
          onDone: () {
            buffer.clear();
            out.close();
          },
          cancelOnError: false,
        );
      },
      onPause: () => sub?.pause(),
      onResume: () => sub?.resume(),
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }

  /// Index of [pattern] in [data] at or after [from], or -1 if absent.
  static int _indexOf(List<int> data, List<int> pattern, int from) {
    if (pattern.isEmpty) return -1;
    final last = data.length - pattern.length;
    for (var i = from; i <= last; i++) {
      var match = true;
      for (var j = 0; j < pattern.length; j++) {
        if (data[i + j] != pattern[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }
}

/// Serial-friendly reading helpers on a byte stream such as
/// [BtcConnection.input] or [BtcReconnectingConnection.input].
///
/// {@category Models}
extension BtcByteStreamReader on Stream<Uint8List> {
  /// Splits this stream into [delimiter]-separated frames (delimiter stripped),
  /// reassembling frames that span multiple chunks. See [BtcFrameSplitter].
  Stream<Uint8List> frames({
    List<int> delimiter = const [0x0A],
    int? maxFrameLength,
  }) => transform(
    BtcFrameSplitter(delimiter: delimiter, maxFrameLength: maxFrameLength),
  );

  /// Emits decoded text lines. Splits on `\n`, strips a trailing `\r` so both
  /// `\n`- and `\r\n`-terminated devices read cleanly, and decodes each line
  /// with [encoding] (UTF-8 by default).
  ///
  /// ```dart
  /// connection.input.lines().listen((line) => print('> $line'));
  /// ```
  Stream<String> lines({Encoding encoding = utf8, int? maxLineLength}) =>
      frames(delimiter: const [0x0A], maxFrameLength: maxLineLength).map((f) {
        final end = (f.isNotEmpty && f.last == 0x0D) ? f.length - 1 : f.length;
        return encoding.decode(f.sublist(0, end));
      });

  /// Decodes incoming bytes to text as they arrive, correctly handling
  /// multi-byte characters split across chunk boundaries. Not line-buffered.
  Stream<String> decoded({Encoding encoding = utf8}) =>
      cast<List<int>>().transform(encoding.decoder);
}
