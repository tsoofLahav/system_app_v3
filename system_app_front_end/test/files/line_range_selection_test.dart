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

  test('wordSelectionAround marks Hebrew and English words', () {
    expect(
      'hello world'.substring(
        wordSelectionAround('hello world', 1).start,
        wordSelectionAround('hello world', 1).end,
      ),
      'hello',
    );
    const hebrew = 'בדיקת איכות עכשיו';
    final mark = wordSelectionAround(hebrew, 8);
    expect(hebrew.substring(mark.start, mark.end), 'איכות');
  });

  test('wordSelectionAround keeps mixed Hebrew, English, and numbers apart', () {
    const mixed = 'אני Flutter 3 היום';
    expect(mixed.substring(0, 3), 'אני');
    expect(
      mixed.substring(
        wordSelectionAround(mixed, 1).start,
        wordSelectionAround(mixed, 1).end,
      ),
      'אני',
    );
    expect(
      mixed.substring(
        wordSelectionAround(mixed, 6).start,
        wordSelectionAround(mixed, 6).end,
      ),
      'Flutter',
    );
    expect(
      mixed.substring(
        wordSelectionAround(mixed, 12).start,
        wordSelectionAround(mixed, 12).end,
      ),
      '3',
    );
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
