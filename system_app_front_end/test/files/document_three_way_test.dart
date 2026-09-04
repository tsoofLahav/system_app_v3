import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/editor/document_hunks.dart';
import 'package:system_app_front_end/areas/files/editor/document_three_way.dart';
import 'package:system_app_front_end/areas/files/model/document_text_codec.dart';

String _doc(String body) => DocumentTextCodec.wrap(body);

void main() {
  test('one-sided local edit applies without a conflict', () {
    final result = threeWayMarkerText(
      base: _doc('hello'),
      local: _doc('hello\n\nlocal'),
      server: _doc('hello'),
    );
    expect(result.hasConflicts, isFalse);
    expect(splitMarkerParts(result.merged), ['hello', 'local']);
  });

  test('one-sided server edit applies without a conflict', () {
    final result = threeWayMarkerText(
      base: _doc('hello'),
      local: _doc('hello'),
      server: _doc('hello\n\nserver'),
    );
    expect(result.hasConflicts, isFalse);
    expect(splitMarkerParts(result.merged), ['hello', 'server']);
  });

  test('identical both-sides change applies once', () {
    final result = threeWayMarkerText(
      base: _doc('hello'),
      local: _doc('hi'),
      server: _doc('hi'),
    );
    expect(result.hasConflicts, isFalse);
    expect(splitMarkerParts(result.merged), ['hi']);
  });

  test('edits in different parts both apply', () {
    final result = threeWayMarkerText(
      base: _doc('a\n\nb'),
      local: _doc('A\n\nb'),
      server: _doc('a\n\nB'),
    );
    expect(result.hasConflicts, isFalse);
    expect(splitMarkerParts(result.merged), ['A', 'B']);
  });

  test('overlap leaves hunks only on the conflicting part', () {
    final result = threeWayMarkerText(
      base: _doc('keep\n\nmiddle\n\nend'),
      local: _doc('keep\n\nLOCAL\n\nend'),
      server: _doc('keep\n\nSERVER\n\nend'),
    );
    expect(result.hasConflicts, isTrue);
    expect(splitMarkerParts(result.localSided), ['keep', 'LOCAL', 'end']);
    expect(splitMarkerParts(result.serverSided), ['keep', 'SERVER', 'end']);
    final hunks = buildHunks(result.localSided, result.serverSided);
    expect(hunks, isNotEmpty);
    expect(
      hunks.any((h) => h.oldLines.join().contains('LOCAL')),
      isTrue,
    );
    expect(
      hunks.any((h) => h.newLines.join().contains('SERVER')),
      isTrue,
    );
    expect(
      hunks.any((h) => h.oldLines.join() == 'keep' || h.newLines.join() == 'keep'),
      isFalse,
    );
  });
}
