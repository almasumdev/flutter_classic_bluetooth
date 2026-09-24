import 'dart:async';
import 'dart:typed_data';

/// Splits a byte stream into frames that each begin with their own length,
/// buffering across chunk boundaries so a frame may span several reads. The
/// length prefix is stripped from the emitted frames.
///
/// RFCOMM preserves no message boundaries, so a binary protocol usually states
/// how long each message is instead of ending it with a delimiter. That is the
/// case a delimiter cannot serve: payload bytes are free to take any value,
/// including whatever the delimiter would have been. Use
/// [BtcFrameSplitter] for text protocols that end each line, and this for
/// binary ones that count.
///
/// ```dart
/// connection.input
///     .transform(const BtcLengthFrameSplitter()) // one leading length byte
///     .listen(handleMessage);
/// ```
///
/// A partial frame is never emitted: the transformer waits until the whole
/// payload has arrived. If a declared length exceeds [maxFrameLength] the
/// stream emits a [StateError] and drops everything buffered, which is the
/// guard against a desynchronised stream reserving memory without bound.
///
/// {@category Models}
class BtcLengthFrameSplitter
    extends StreamTransformerBase<Uint8List, Uint8List> {
  /// Creates a splitter for frames prefixed with their length.
  ///
  /// [prefixLength] is the size of that prefix in bytes and must be 1, 2 or 4.
  /// [bigEndian] selects the byte order of the prefix, network order by
  /// default. Set [lengthIncludesPrefix] when the number counts its own prefix
  /// bytes as well as the payload, which some protocols do.
  const BtcLengthFrameSplitter({
    this.prefixLength = 1,
    this.bigEndian = true,
    this.lengthIncludesPrefix = false,
    this.maxFrameLength,
  }) : assert(
         prefixLength == 1 || prefixLength == 2 || prefixLength == 4,
         'prefixLength must be 1, 2 or 4',
       );

  /// How many bytes carry the length: 1, 2 or 4.
  final int prefixLength;

  /// Whether the length prefix is most significant byte first.
  final bool bigEndian;

  /// Whether the declared length counts the prefix bytes as well as the
  /// payload.
  final bool lengthIncludesPrefix;

  /// Optional cap on a declared payload length before erroring.
  final int? maxFrameLength;

  @override
  Stream<Uint8List> bind(Stream<Uint8List> stream) {
    final buffer = <int>[];
    StreamSubscription<Uint8List>? sub;
    late StreamController<Uint8List> out;

    void onData(Uint8List chunk) {
      buffer.addAll(chunk);
      while (buffer.length >= prefixLength) {
        var payloadLength = _readLength(buffer);
        if (lengthIncludesPrefix) payloadLength -= prefixLength;

        // A negative or oversized length means the stream is not where it
        // claims to be, and reading on would only compound it.
        if (payloadLength < 0 ||
            (maxFrameLength != null && payloadLength > maxFrameLength!)) {
          buffer.clear();
          out.addError(
            StateError(
              'Frame length $payloadLength is not usable '
              '(maxFrameLength: $maxFrameLength)',
            ),
          );
          return;
        }

        final total = prefixLength + payloadLength;
        if (buffer.length < total) return; // the rest is still in flight
        out.add(Uint8List.fromList(buffer.sublist(prefixLength, total)));
        buffer.removeRange(0, total);
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

  /// Reads the length prefix from the front of [buffer].
  int _readLength(List<int> buffer) {
    var value = 0;
    for (var i = 0; i < prefixLength; i++) {
      final byte = buffer[bigEndian ? i : prefixLength - 1 - i];
      value = (value << 8) | byte;
    }
    return value;
  }

  /// Writes [payload] with the matching length prefix, ready to send.
  ///
  /// The counterpart to reading: a device that frames its replies this way
  /// usually expects the same shape back.
  ///
  /// Throws an [ArgumentError] when the payload is too long for the prefix to
  /// describe.
  Uint8List frame(List<int> payload) {
    final declared = lengthIncludesPrefix
        ? payload.length + prefixLength
        : payload.length;
    final limit = (1 << (prefixLength * 8)) - 1;
    if (declared > limit) {
      throw ArgumentError.value(
        payload.length,
        'payload',
        'too long for a $prefixLength-byte length prefix (max $limit)',
      );
    }
    final out = Uint8List(prefixLength + payload.length);
    for (var i = 0; i < prefixLength; i++) {
      final shift = 8 * (bigEndian ? prefixLength - 1 - i : i);
      out[i] = (declared >> shift) & 0xFF;
    }
    out.setRange(prefixLength, out.length, payload);
    return out;
  }
}
