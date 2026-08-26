import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/rich_text/formatted_text_field.dart';
import 'package:system_app_front_end/areas/files/rich_text/rtl/rtl.dart';

void main() {
  group('pickCaretPaintRect', () {
    test('end of wrapped line prefers the rect on the glyph line', () {
      const glyph = Rect.fromLTRB(100, 0, 110, 16);
      const down = Rect.fromLTRB(0, 16, 2, 32);
      const up = Rect.fromLTRB(110, 0, 112, 16);
      expect(
        pickCaretPaintRect(
          downstream: down,
          upstream: up,
          glyph: glyph,
          glyphDirection: TextDirection.ltr,
          caretBeforeGlyph: false,
        ),
        up,
      );
    });

    test('Hebrew insertion prefers the trailing (left) edge', () {
      const glyph = Rect.fromLTRB(80, 0, 92, 16);
      const ahead = Rect.fromLTRB(92, 0, 94, 16);
      const atInsert = Rect.fromLTRB(78, 0, 80, 16);
      expect(
        pickCaretPaintRect(
          downstream: ahead,
          upstream: atInsert,
          glyph: glyph,
          glyphDirection: TextDirection.rtl,
          caretBeforeGlyph: false,
        ),
        atInsert,
      );
    });

    test('caret before first glyph uses the leading edge', () {
      const glyph = Rect.fromLTRB(8, 0, 20, 16);
      const atStart = Rect.fromLTRB(6, 0, 8, 16);
      const after = Rect.fromLTRB(20, 0, 22, 16);
      expect(
        pickCaretPaintRect(
          downstream: after,
          upstream: atStart,
          glyph: glyph,
          glyphDirection: TextDirection.ltr,
          caretBeforeGlyph: true,
        ),
        atStart,
      );
    });

    test('no glyph falls back to downstream', () {
      const down = Rect.fromLTRB(0, 0, 2, 16);
      const up = Rect.fromLTRB(40, 0, 42, 16);
      expect(
        pickCaretPaintRect(
          downstream: down,
          upstream: up,
          glyph: null,
          glyphDirection: TextDirection.ltr,
          caretBeforeGlyph: false,
        ),
        down,
      );
    });
  });

  testWidgets('object field hides the native cursor and paints an overlay', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'שלום');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FormattedTextField(
            controller: controller,
            style: const TextStyle(fontSize: 14, color: Color(0xFF111111)),
            maxLines: null,
          ),
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.showCursor, isFalse);
    expect(find.byType(EmbedCaretOverlay), findsOneWidget);

    await tester.tap(find.byType(FormattedTextField));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
  });
}
