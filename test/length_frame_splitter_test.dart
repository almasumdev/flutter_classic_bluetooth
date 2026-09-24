import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';
import 'package:flutter_test/flutter_test.dart';

/// Feeds [chunks] through [splitter] and collects the frames it emits.
Future<List<List<int>>> _run(
  BtcLengthFrameSplitter splitter,
  List<List<int>> chunks, {
  List<Object>? errors,
}) async {
  final controller = StreamController<Uint8List>();
  final frames = <List<int>>[];
  final done = Completer<void>();
  splitter
      .bind(controller.stream)
      .listen(
        (f) => frames.add(f.toList()),
        onError: (Object e) => errors?.add(e),
        onDone: done.complete,
      );
  for (final chunk in chunks) {
    controller.add(Uint8List.fromList(chunk));
    await Future<void>.delayed(Duration.zero);
  }
  await controller.close();
  await done.future;
  return frames;
}

void main() {
  group('Length Frame Splitter', () {
    test('a single frame comes back without its prefix', () async {
      final frames = await _run(const BtcLengthFrameSplitter(), [
        [3, 10, 20, 30],
      ]);
      expect(frames, [
        [10, 20, 30],
      ]);
    });

    test('several frames in one chunk all come out', () async {
      final frames = await _run(const BtcLengthFrameSplitter(), [
        [2, 1, 2, 3, 7, 8, 9, 1, 0],
      ]);
      expect(frames, [
        [1, 2],
        [7, 8, 9],
        [0],
      ]);
    });

    test('a frame split across chunks is reassembled', () async {
      final frames = await _run(const BtcLengthFrameSplitter(), [
        [4, 1],
        [2, 3],
        [4],
      ]);
      expect(frames, [
        [1, 2, 3, 4],
      ]);
    });

    test('a prefix split across chunks is handled', () async {
      final frames = await _run(const BtcLengthFrameSplitter(prefixLength: 2), [
        [0],
        [3, 5, 6, 7],
      ]);
      expect(frames, [
        [5, 6, 7],
      ]);
    });

    test('an empty payload is a real frame', () async {
      final frames = await _run(const BtcLengthFrameSplitter(), [
        [0, 1, 9],
      ]);
      expect(frames, [
        <int>[],
        [9],
      ]);
    });

    test('a payload byte equal to the delimiter is not a boundary', () async {
      // The case a delimiter splitter cannot serve: a newline inside binary
      // data is just data here.
      final frames = await _run(const BtcLengthFrameSplitter(), [
        [3, 0x0A, 0x0A, 0x0A],
      ]);
      expect(frames, [
        [0x0A, 0x0A, 0x0A],
      ]);
    });

    test('an unfinished frame is never emitted', () async {
      final frames = await _run(const BtcLengthFrameSplitter(), [
        [5, 1, 2],
      ]);
      expect(frames, isEmpty);
    });

    test('a two-byte prefix is read big-endian by default', () async {
      final payload = List<int>.filled(300, 7);
      final frames = await _run(const BtcLengthFrameSplitter(prefixLength: 2), [
        [0x01, 0x2C, ...payload],
      ]);
      expect(frames.single, hasLength(300));
    });

    test('little-endian is read the other way round', () async {
      final payload = List<int>.filled(300, 7);
      final frames = await _run(
        const BtcLengthFrameSplitter(prefixLength: 2, bigEndian: false),
        [
          [0x2C, 0x01, ...payload],
        ],
      );
      expect(frames.single, hasLength(300));
    });

    test('a four-byte prefix works', () async {
      final frames = await _run(const BtcLengthFrameSplitter(prefixLength: 4), [
        [0, 0, 0, 2, 42, 43],
      ]);
      expect(frames, [
        [42, 43],
      ]);
    });

    test('a length that counts its own prefix is handled', () async {
      final frames = await _run(
        const BtcLengthFrameSplitter(lengthIncludesPrefix: true),
        [
          [4, 1, 2, 3],
        ],
      );
      expect(frames, [
        [1, 2, 3],
      ]);
    });

    test(
      'a declared length past the cap errors and drops the buffer',
      () async {
        final errors = <Object>[];
        final frames = await _run(
          const BtcLengthFrameSplitter(maxFrameLength: 4),
          [
            [200, 1, 2, 3],
          ],
          errors: errors,
        );
        expect(frames, isEmpty);
        expect(errors.single, isA<StateError>());
      },
    );

    test('a length shorter than its own prefix errors', () async {
      final errors = <Object>[];
      await _run(const BtcLengthFrameSplitter(lengthIncludesPrefix: true), [
        [0, 9],
      ], errors: errors);
      expect(errors.single, isA<StateError>());
    });

    test('framing then splitting returns the payload unchanged', () async {
      const splitter = BtcLengthFrameSplitter(prefixLength: 2);
      final payload = List<int>.generate(500, (i) => i % 256);
      final wire = splitter.frame(payload);
      final frames = await _run(splitter, [wire]);
      expect(frames.single, payload);
    });

    test('framing honours the byte order and the prefix convention', () {
      expect(const BtcLengthFrameSplitter(prefixLength: 2).frame([9, 9, 9]), [
        0,
        3,
        9,
        9,
        9,
      ]);
      expect(
        const BtcLengthFrameSplitter(
          prefixLength: 2,
          bigEndian: false,
        ).frame([9, 9, 9]),
        [3, 0, 9, 9, 9],
      );
      expect(
        const BtcLengthFrameSplitter(
          lengthIncludesPrefix: true,
        ).frame([9, 9, 9]),
        [4, 9, 9, 9],
      );
    });

    test('framing refuses a payload the prefix cannot describe', () {
      expect(
        () => const BtcLengthFrameSplitter().frame(List<int>.filled(256, 0)),
        throwsArgumentError,
      );
      // One less fits in a single byte.
      expect(
        const BtcLengthFrameSplitter().frame(List<int>.filled(255, 0)),
        hasLength(256),
      );
    });

    test('the lengthFrames stream extension uses it', () async {
      final controller = StreamController<Uint8List>();
      final frames = <List<int>>[];
      final done = Completer<void>();
      controller.stream
          .lengthFrames(prefixLength: 2)
          .listen((f) => frames.add(f.toList()), onDone: done.complete);
      controller.add(Uint8List.fromList([0, 2, 8, 9]));
      await controller.close();
      await done.future;
      expect(frames, [
        [8, 9],
      ]);
    });

    test('a byte at a time still reassembles every frame', () async {
      const splitter = BtcLengthFrameSplitter();
      final wire = [
        ...splitter.frame([1, 2]),
        ...splitter.frame([3]),
        ...splitter.frame([4, 5, 6]),
      ];
      final frames = await _run(splitter, [
        for (final b in wire) [b],
      ]);
      expect(frames, [
        [1, 2],
        [3],
        [4, 5, 6],
      ]);
    });
  });
}
