import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/rich_text/text_formatting.dart';

/// Appending a raw overlapping span to [TextSpanBuilder.build] repaints —
/// and thus visually duplicates — any text a later span overlaps, since it
/// walks spans in order and does not merge them. This is what happened when
/// a done inner-task line's synthetic strikethrough range overlapped an
/// existing connected/description-link span on the same title text.
/// [overlaySpansWithStrikethrough] must merge instead, so the built TextSpan
/// tree reconstructs the original text exactly once.
String _flatten(InlineSpan span) => span.toPlainText();

void main() {
  test('appending an overlapping span duplicates text (the bug)', () {
    const text = 'buy milk please';
    final linkStart = text.indexOf('milk');
    final linkEnd = linkStart + 'milk'.length;
    final spans = [
      {'start': linkStart, 'end': linkEnd, 'descriptionLink': true},
      // Appended, not merged — overlaps the link span above.
      {'start': 0, 'end': text.length, 'strikethrough': true},
    ];
    final built = TextSpanBuilder.build(
      text: text,
      baseStyle: const TextStyle(),
      spans: spans,
    );
    // "milk" is painted once by the link span, then again in full by the
    // strikethrough span — the flattened text is longer than the source.
    expect(_flatten(built).length, greaterThan(text.length));
  });

  test('overlaySpansWithStrikethrough merges instead of duplicating', () {
    const text = 'buy milk please';
    final linkStart = text.indexOf('milk');
    final linkEnd = linkStart + 'milk'.length;
    final spans = [
      {'start': linkStart, 'end': linkEnd, 'descriptionLink': true},
    ];
    final merged = overlaySpansWithStrikethrough(
      spans,
      [(start: 0, end: text.length)],
      text.length,
    );
    final built = TextSpanBuilder.build(
      text: text,
      baseStyle: const TextStyle(),
      spans: merged,
    );
    expect(_flatten(built), text);

    // The connected-link run keeps its style AND gains strikethrough.
    final linkRun = merged.firstWhere(
      (s) => s['descriptionLink'] == true,
    );
    expect(linkRun['strikethrough'], true);
    expect(linkRun['start'], linkStart);
    expect(linkRun['end'], linkEnd);
  });
}
