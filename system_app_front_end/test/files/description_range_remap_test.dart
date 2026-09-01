import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/rich_text/text_formatting.dart';

void main() {
  test('typing before a connected span moves the underline with the text', () {
    const oldText = 'call the clinic';
    const newText = 'please call the clinic';
    final next = remapOffsetRange(
      start: 0,
      end: 15,
      oldText: oldText,
      newText: newText,
    );
    expect(next, isNotNull);
    expect(newText.substring(next!.start, next.end), 'call the clinic');
  });

  test('typing immediately before the span does not eat the new characters', () {
    const oldText = 'clinic';
    const newText = 'the clinic';
    final next = remapOffsetRange(
      start: 0,
      end: 6,
      oldText: oldText,
      newText: newText,
    );
    expect(next, isNotNull);
    expect(newText.substring(next!.start, next.end), 'clinic');
  });

  test('insert inside the span grows the underline', () {
    const oldText = 'call clinic';
    const newText = 'call the clinic';
    final next = remapOffsetRange(
      start: 0,
      end: 11,
      oldText: oldText,
      newText: newText,
    );
    expect(next, isNotNull);
    expect(newText.substring(next!.start, next.end), 'call the clinic');
  });

  test('deleting the connected glyphs drops the range', () {
    const oldText = 'xx clinic yy';
    const newText = 'xx  yy';
    final next = remapOffsetRange(
      start: 3,
      end: 9,
      oldText: oldText,
      newText: newText,
    );
    expect(next, isNull);
  });
}
