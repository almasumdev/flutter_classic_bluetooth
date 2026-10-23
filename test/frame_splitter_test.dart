import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BtcFrameSplitter', () {
    Uint8List b(String s) => Uint8List.fromList(s.codeUnits);

    test('emits frames split on the delimiter, delimiter stripped', () async {
      final src = StreamController<Uint8List>();
      final out = src.stream.frames().map(String.fromCharCodes).toList();
      src
        ..add(b('one\ntwo\n'))
        ..add(b('three\n'));
      await src.close();
      expect(await out, ['one', 'two', 'three']);
    });

    test('reassembles a frame split across chunks', () async {
      final src = StreamController<Uint8List>();
      final out = src.stream.frames().map(String.fromCharCodes).toList();
      src
        ..add(b('hel'))
        ..add(b('lo\nwor'))
        ..add(b('ld\n'));
      await src.close();
      expect(await out, ['hello', 'world']);
    });

    test('does not emit a trailing un-terminated remainder', () async {
      final src = StreamController<Uint8List>();
      final out = src.stream.frames().map(String.fromCharCodes).toList();
      src.add(b('done\npartial'));
      await src.close();
      expect(await out, ['done']);
    });

    test('supports a multi-byte delimiter', () async {
      final src = StreamController<Uint8List>();
      final out = src.stream
          .frames(delimiter: const [0x0D, 0x0A]) // \r\n
          .map(String.fromCharCodes)
          .toList();
      src.add(b('a\r\nb\r\n'));
      await src.close();
      expect(await out, ['a', 'b']);
    });

    test('lines() decodes and strips a trailing CR (\\r\\n)', () async {
      final src = StreamController<Uint8List>();
      final out = src.stream.lines().toList();
      src.add(b('crlf\r\nlf\n'));
      await src.close();
      expect(await out, ['crlf', 'lf']);
    });

    test('errors and drops the buffer past maxFrameLength', () async {
      final src = StreamController<Uint8List>();
      final errors = <Object>[];
      final frames = <String>[];
      final done = Completer<void>();
      src.stream
          .frames(maxFrameLength: 4)
          .listen(
            (f) => frames.add(String.fromCharCodes(f)),
            onError: errors.add,
            onDone: done.complete,
          );
      src.add(b('toolong')); // 7 bytes, no delimiter
      src.add(b('ok\n'));
      await src.close();
      await done.future;
      expect(errors, hasLength(1));
      expect(errors.first, isA<StateError>());
      expect(frames, ['ok']); // recovered after the buffer was dropped
    });
  });

  // ── Auto-reconnect ────────────────────────────────────────────────────
  group('BtcFrameSplitter Across Chunk Boundaries', () {
    Uint8List b(String s) => Uint8List.fromList(s.codeUnits);

    /// Feeds [text] one chunk of [size] bytes at a time and collects frames.
    Future<List<String>> split(
      String text, {
      int size = 1,
      List<int> delimiter = const [0x0A],
    }) async {
      final src = StreamController<Uint8List>();
      final out = src.stream
          .frames(delimiter: delimiter)
          .map(String.fromCharCodes)
          .toList();
      for (var i = 0; i < text.length; i += size) {
        src.add(b(text.substring(i, (i + size).clamp(0, text.length))));
      }
      await src.close();
      return out;
    }

    test('a multi-byte delimiter split across chunks is still found', () async {
      // The search resumes where the last chunk stopped, so it has to back up
      // far enough to catch a delimiter that started in the previous chunk.
      for (final size in [1, 2, 3, 5]) {
        expect(
          await split(
            'one\r\ntwo\r\nthree\r\n',
            size: size,
            delimiter: [13, 10],
          ),
          ['one', 'two', 'three'],
          reason: 'chunks of $size',
        );
      }
    });

    test('a long delimiter is found at every split offset', () async {
      const text = 'alpha<END>beta<END>';
      for (var size = 1; size <= text.length; size++) {
        expect(await split(text, size: size, delimiter: '<END>'.codeUnits), [
          'alpha',
          'beta',
        ], reason: 'chunks of $size');
      }
    });

    test('a long frame arriving a byte at a time is reassembled', () async {
      final long = 'x' * 5000;
      expect(await split('$long\nshort\n'), [long, 'short']);
    });

    test('a delimiter whose prefix repeats is matched correctly', () async {
      // `aab` inside `aaab`: a search that resumed too far forward would skip
      // the real match.
      expect(await split('xaaab-yaaab', size: 1, delimiter: 'aab'.codeUnits), [
        'xa',
        '-ya',
      ]);
    });

    test('a long frame in small chunks is not quadratic', () async {
      // A 128 KB frame in 20-byte chunks took about 340 ms when every chunk
      // searched the whole buffer again, and about 20 ms once it does not.
      final src = StreamController<Uint8List>();
      final frames = src.stream.frames().toList();
      final sw = Stopwatch()..start();
      final chunk = Uint8List.fromList(List.filled(20, 0x41));
      for (var i = 0; i < 128000; i += 20) {
        src.add(chunk);
      }
      src.add(Uint8List.fromList([0x0A]));
      await src.close();
      expect(await frames, hasLength(1));
      expect(sw.elapsedMilliseconds, lessThan(200));
    });

    test('an empty delimiter is rejected rather than never matching', () {
      final src = StreamController<Uint8List>();
      expect(
        () => src.stream.transform(const BtcFrameSplitter(delimiter: [])),
        throwsArgumentError,
      );
    });

    test('maxFrameLength still resets the search after dropping', () async {
      final src = StreamController<Uint8List>();
      final frames = <String>[];
      final errors = <Object>[];
      // asFuture would replace onError and fail on the expected error, so the
      // end of the stream is awaited through onDone instead.
      final done = Completer<void>();
      src.stream
          .frames(maxFrameLength: 8)
          .map(String.fromCharCodes)
          .listen(frames.add, onError: errors.add, onDone: done.complete);
      src
        ..add(b('0123456789'))
        ..add(b('ok\n'));
      await src.close();
      await done.future;
      expect(errors, hasLength(1));
      expect(frames, ['ok']);
    });
  });
}
