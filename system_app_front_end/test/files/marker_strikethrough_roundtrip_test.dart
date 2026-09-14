import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:system_app_front_end/areas/files/model/marker_super_editor_bridge.dart';

void main() {
  test(
    'spaced strike preserves nested formatting and literal code/escapes',
    () {
      final nested = markerLineToAttributedText('~~**שלום**  ~~');
      expect(nested.toPlainText(), 'שלום  ');
      expect(
        nested.getAllAttributionsAt(0),
        containsAll([boldAttribution, strikethroughAttribution]),
      );
      expect(
        markerLineToAttributedText(r'\~שלום  \~').toPlainText(),
        '~שלום  ~',
      );
      final code = markerLineToAttributedText('`~שלום  ~`');
      expect(code.toPlainText(), '~שלום  ~');
      expect(
        code.getAllAttributionsAt(0),
        isNot(contains(strikethroughAttribution)),
      );
    },
  );
  for (final plain in [
    'אח את העניין ש להאדיטור',
    'אח את העניין ש להאדיטור  ',
    '  שלום 123  ',
    'שלום\nעולם  ',
  ]) {
    test('strikethrough preserves text and spaces: $plain', () {
      final text = AttributedText(plain)
        ..addAttribution(
          strikethroughAttribution,
          SpanRange(0, plain.length - 1),
        );
      final encoded = attributedTextToMarkerLine(text);
      final restored = markerLineToAttributedText(encoded);
      expect(restored.toPlainText(), plain, reason: encoded);
      expect(
        restored.getAllAttributionsAt(
          plain.indexOf('א') < 0 ? plain.indexOf('ש') : 0,
        ),
        contains(strikethroughAttribution),
      );
    });
  }
}
