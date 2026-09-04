import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/editor/document_hunks.dart';

void main() {
  test('single line edit is one change hunk', () {
    const old = 'a\nb\nc\n';
    const next = 'a\nB\nc\n';
    final hunks = buildHunks(old, next);
    expect(hunks, hasLength(1));
    expect(hunks.single.op, 'change');
    expect(hunks.single.oldLines, ['b']);
    expect(hunks.single.newLines, ['B']);
  });

  test('accept change replaces and does not keep both lines', () {
    const old = 'a\nb\nc\n';
    const next = 'a\nB\nc\n';
    final hunks = buildHunks(old, next);
    final text = mergeHunkTexts(old, next, [
      for (final h in hunks) {'hunk_id': h.id, 'choice': 'accept'},
    ]);
    expect(text!.trim().split('\n'), ['a', 'B', 'c']);
  });

  test('pure insert and delete', () {
    expect(buildHunks('a\nc\n', 'a\nb\nc\n').single.op, 'add');
    expect(buildHunks('a\nb\nc\n', 'a\nc\n').single.op, 'remove');
  });

  test('merge reject all keeps old', () {
    const old = 'one\ntwo\n';
    const next = 'one\nTWO\n';
    final hunks = buildHunks(old, next);
    final text = mergeHunkTexts(old, next, [
      for (final h in hunks) {'hunk_id': h.id, 'choice': 'reject'},
    ]);
    expect(text!.contains('two'), isTrue);
    expect(text.contains('TWO'), isFalse);
  });

  test('merge requires every hunk', () {
    expect(mergeHunkTexts('one\ntwo\n', 'one\nTWO\nthree\n', []), isNull);
  });
}
