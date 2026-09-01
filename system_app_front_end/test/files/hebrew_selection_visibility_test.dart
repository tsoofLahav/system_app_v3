import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:system_app_front_end/areas/files/editor/selection_background_phase.dart';

void main() {
  testWidgets('Hebrew expanded selection gets a background attribution',
      (tester) async {
    const hebrew = 'שלום עולם';
    final doc = MutableDocument(nodes: [
      ParagraphNode(id: '1', text: AttributedText(hebrew)),
    ]);
    final composer = MutableDocumentComposer(
      initialSelection: const DocumentSelection(
        base: DocumentPosition(
          nodeId: '1',
          nodePosition: TextNodePosition(offset: 0),
        ),
        extent: DocumentPosition(
          nodeId: '1',
          nodePosition: TextNodePosition(offset: 9),
        ),
      ),
    );
    final editor = createDefaultDocumentEditor(
      document: doc,
      composer: composer,
    );
    const wash = Color(0xFF9CC8D4);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SuperEditor(
            editor: editor,
            plugins: {VisibleSelectionPlugin(color: wash)},
            selectionStyle: const SelectionStyles(selectionColor: wash),
            stylesheet: Stylesheet(
              documentPadding: EdgeInsets.zero,
              inlineTextStyler: defaultInlineTextStyler,
              rules: [
                StyleRule(
                  BlockSelector.all,
                  (doc, node) => {
                    Styles.maxWidth: double.infinity,
                    Styles.textAlign: TextAlign.start,
                    Styles.textStyle: const TextStyle(
                      fontSize: 16,
                      color: Colors.black,
                    ),
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final node = doc.getNodeById('1')! as TextNode;
    // The attribution lives on the layout view model, not the document node.
    // Assert via the rendered text span background instead.
    final richTexts = find.byWidgetPredicate(
      (w) =>
          w is RichText &&
          _spanHasBackground(w.text, wash),
    );
    expect(richTexts, findsWidgets);
    expect(node.text.toPlainText(), hebrew);
  });
}

bool _spanHasBackground(InlineSpan span, Color color) {
  if (span is TextSpan) {
    if (span.style?.backgroundColor == color) return true;
    final children = span.children;
    if (children != null) {
      for (final child in children) {
        if (_spanHasBackground(child, color)) return true;
      }
    }
  }
  return false;
}
