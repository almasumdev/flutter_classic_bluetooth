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
      src.stream.frames(maxFrameLength: 4).listen(
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
}
