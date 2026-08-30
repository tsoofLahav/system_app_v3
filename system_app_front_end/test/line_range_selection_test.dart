import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/model/line_range.dart';
import 'package:system_app_front_end/areas/files/rich_text/formatted_text_field.dart';

void main() {
  test('caret line does not include the trailing newline', () {
    const text = 'first\nsecond\nthird';
    final range = LineRange.resolve(
      text,
      const TextSelection.collapsed(offset: 8),
    );
    expect(text.substring(range.start, range.end), 'second');
  });

  test('word/line select drops an edge newline so RTL does not paint a trail', () {
    const text = 'קפסולת ניקיון.\nnext';
    final withNewline = TextSelection(
      baseOffset: 0,
      extentOffset: text.indexOf('\n') + 1,
    );
    final clipped = LineRange.withoutEdgeNewlines(text, withNewline);
    expect(text.substring(clipped.start, clipped.end), 'קפסולת ניקיון.');
    expect(clipped.end, text.indexOf('\n'));
  });

  test('a multi-line mark keeps the newline between lines', () {
    const text = 'one\ntwo\nthree';
    const mark = TextSelection(baseOffset: 0, extentOffset: 8);
    final clipped = LineRange.withoutEdgeNewlines(text, mark);
    expect(text.substring(clipped.start, clipped.end), 'one\ntwo');
  });

  test('embed caret correction skips the second tap of a double-click', () {
    expect(
      shouldApplyEmbedCaretForTap(
        draggedBeyondSlop: false,
        selectionIsRange: false,
        shiftPressed: false,
        consecutiveTapCount: 2,
      ),
      isFalse,
    );
  });
}
