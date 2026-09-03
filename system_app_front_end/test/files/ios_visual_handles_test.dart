import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:system_app_front_end/areas/files/rich_text/rtl/ios_visual_handles.dart';

void main() {
  testWidgets(
    'Hebrew upstream is the right of the word, downstream the left',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      const hebrew = 'בדיקת איכות עכשיו';
      const selection = DocumentSelection(
        base: DocumentPosition(
          nodeId: '1',
          nodePosition: TextNodePosition(offset: 6),
        ),
        extent: DocumentPosition(
          nodeId: '1',
          nodePosition: TextNodePosition(offset: 11),
        ),
      );
      final (layout, doc) = await _pumpEditor(
        tester,
        text: hebrew,
        selection: selection,
        textDirection: TextDirection.rtl,
      );
      final handles = visualIosExpandedHandleLayout(
        document: doc,
        documentLayout: layout,
        selection: selection,
      );
      final word = layout.getRectForSelection(selection.base, selection.extent);
      final line = layout.getRectForSelection(
        const DocumentPosition(
          nodeId: '1',
          nodePosition: TextNodePosition(offset: 0),
        ),
        DocumentPosition(
          nodeId: '1',
          nodePosition: TextNodePosition(offset: hebrew.length),
        ),
      );
      expect(handles, isNotNull);
      expect(word, isNotNull);
      expect(line, isNotNull);
      expect(handles!.upstream!.left, closeTo(word!.right, 1));
      expect(handles.downstream!.left, closeTo(word.left, 1));
      expect(handles.upstream!.left, greaterThan(handles.downstream!.left));
      expect(
        (handles.upstream!.left - word.right).abs(),
        lessThan((handles.upstream!.left - line!.left).abs()),
      );
      expect(
        (handles.downstream!.left - word.left).abs(),
        lessThan((handles.downstream!.left - line.right).abs()),
      );
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('English upstream is the left of the word, downstream the right', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    const english = 'The quality check now';
    const selection = DocumentSelection(
      base: DocumentPosition(
        nodeId: '1',
        nodePosition: TextNodePosition(offset: 4),
      ),
      extent: DocumentPosition(
        nodeId: '1',
        nodePosition: TextNodePosition(offset: 11),
      ),
    );
    final (layout, doc) = await _pumpEditor(
      tester,
      text: english,
      selection: selection,
      textDirection: TextDirection.ltr,
    );
    final handles = visualIosExpandedHandleLayout(
      document: doc,
      documentLayout: layout,
      selection: selection,
    );
    final word = layout.getRectForSelection(selection.base, selection.extent);
    final line = layout.getRectForSelection(
      const DocumentPosition(
        nodeId: '1',
        nodePosition: TextNodePosition(offset: 0),
      ),
      DocumentPosition(
        nodeId: '1',
        nodePosition: TextNodePosition(offset: english.length),
      ),
    );
    expect(handles, isNotNull);
    expect(word, isNotNull);
    expect(line, isNotNull);
    expect(handles!.upstream!.left, closeTo(word!.left, 1));
    expect(handles.downstream!.left, closeTo(word.right, 1));
    expect(handles.downstream!.left, greaterThan(handles.upstream!.left));
    expect(
      (handles.upstream!.left - word.left).abs(),
      lessThan((handles.upstream!.left - line!.right).abs()),
    );
    debugDefaultTargetPlatformOverride = null;
  });
}

Future<(DocumentLayout, MutableDocument)> _pumpEditor(
  WidgetTester tester, {
  required String text,
  required DocumentSelection selection,
  required TextDirection textDirection,
}) async {
  final layoutKey = GlobalKey();
  final doc = MutableDocument(
    nodes: [ParagraphNode(id: '1', text: AttributedText(text))],
  );
  final composer = MutableDocumentComposer(initialSelection: selection);
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: textDirection,
        child: SuperEditor(
          editor: createDefaultDocumentEditor(
            document: doc,
            composer: composer,
          ),
          documentLayoutKey: layoutKey,
          stylesheet: Stylesheet(
            documentPadding: EdgeInsets.zero,
            inlineTextStyler: defaultInlineTextStyler,
            rules: [
              StyleRule(BlockSelector.all, (doc, node) => {
                Styles.maxWidth: double.infinity,
                Styles.textAlign: TextAlign.start,
                Styles.textStyle: const TextStyle(fontSize: 16),
              }),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return (layoutKey.currentState as DocumentLayout, doc);
}
