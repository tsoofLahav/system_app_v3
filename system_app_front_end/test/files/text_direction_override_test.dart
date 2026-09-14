import 'package:flutter/material.dart';
import 'package:system_app_front_end/areas/files/editor/embeds/object_embed_widgets.dart';
import 'package:system_app_front_end/areas/files/model/document_model.dart'
    show DocumentTableCell;
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:system_app_front_end/areas/files/model/marker_super_editor_bridge.dart';
import 'package:system_app_front_end/areas/files/model/agent_text_blocks.dart';
import 'package:system_app_front_end/areas/files/editor/read_only_document_view.dart';
import 'package:system_app_front_end/areas/files/rich_text/span_text_editing_controller.dart';
import 'package:system_app_front_end/areas/files/rich_text/format_range.dart';
import 'package:system_app_front_end/areas/files/rich_text/rtl/rtl.dart';

void main() {
  for (final body in [
    '[DIR rtl]hello 123',
    '[DIR ltr]# שלום',
    '[DIR rtl]',
    '[BULLET_LIST]\n- [DIR rtl]hello\n[/BULLET_LIST]',
  ]) {
    test('direction round trip: $body', () {
      final source = '%%system_app_document v4\n$body';
      final doc = markerTextToMutableDocument(source);
      expect(mutableDocumentToMarkerText(doc), source);
      expect(
        (doc.getNodeAt(0)! as TextNode).text.toPlainText(),
        isNot(contains('[DIR')),
      );
      expect(doc.getNodeAt(0)!.getMetadataValue('writingDirection'), isNotNull);
    });
  }
  test('explicit paragraph direction overrides default', () {
    final doc = markerTextToMutableDocument('[DIR ltr]שלום');
    final vm = ambientAwareTextBuilders(
      TextDirection.rtl,
    )[1].createViewModel(doc, doc.getNodeAt(0)!);
    expect(
      (vm as ParagraphComponentViewModel).textDirection,
      TextDirection.ltr,
    );
  });
  test('object override covers field, preserves bold and survives reload', () {
    final controller = SpanTextEditingController(
      text: 'שלום\nhello',
      spans: [
        {'start': 0, 'end': 4, 'bold': true},
      ],
    );
    controller.applyFormatAction(
      'text:direction:ltr',
      range: const FormatRange(start: 6, end: 8),
      baseFontSize: 14,
    );
    expect(controller.directionOverride, TextDirection.ltr);
    expect(controller.text, 'שלום\nhello');
    expect(controller.spans.first['bold'], true);
    final restored = SpanTextEditingController(
      text: controller.text,
      spans: controller.spans,
    );
    expect(restored.directionOverride, TextDirection.ltr);
    restored.applyFormatAction(
      'text:direction:auto',
      range: const FormatRange(start: 6, end: 8),
      baseFontSize: 14,
    );
    expect(restored.directionOverride, isNull);
    expect(restored.spans.first['bold'], true);
    restored.dispose();
    controller.dispose();
  });
  test(
    'paragraph direction selection is undoable and excludes next paragraph start',
    () {
      final first = ParagraphNode(id: 'a', text: AttributedText('שלום'));
      final second = ParagraphNode(id: 'b', text: AttributedText('hello'));
      final doc = MutableDocument(nodes: [first, second]);
      final composer = MutableDocumentComposer();
      final editor = createDefaultDocumentEditor(
        document: doc,
        composer: composer,
        isHistoryEnabled: true,
      );
      const selection = DocumentSelection(
        base: DocumentPosition(
          nodeId: 'a',
          nodePosition: TextNodePosition(offset: 2),
        ),
        extent: DocumentPosition(
          nodeId: 'b',
          nodePosition: TextNodePosition(offset: 0),
        ),
      );
      editor.execute(paragraphDirectionRequests(doc, selection, 'ltr'));
      expect(doc.getNodeById('a')!.getMetadataValue('writingDirection'), 'ltr');
      expect(
        doc.getNodeById('b')!.getMetadataValue('writingDirection'),
        isNull,
      );
      editor.undo();
      expect(
        doc.getNodeById('a')!.getMetadataValue('writingDirection'),
        isNull,
      );
      expect((doc.getNodeById('a')! as TextNode).text.toPlainText(), 'שלום');
      composer.dispose();
    },
  );
  test(
    'object direction survives replacing all text, empty save, and typing again',
    () {
      final controller = SpanTextEditingController(text: 'old');
      controller.applyFormatAction(
        'text:direction:rtl',
        range: const FormatRange(start: 0, end: 3),
        baseFontSize: 14,
      );
      controller.text = 'replacement';
      expect(controller.directionOverride, TextDirection.rtl);
      controller.clear();
      final restored = SpanTextEditingController(
        text: '',
        spans: controller.spans,
      );
      expect(restored.directionOverride, TextDirection.rtl);
      restored.text = '123';
      expect(restored.directionOverride, TextDirection.rtl);
      expect(restored.text, '123');
      restored.dispose();
      controller.dispose();
    },
  );
  test(
    'info and table payloads preserve direction including empty content',
    () {
      for (final text in ['', '\n', 'Title\nbody']) {
        final controller = SpanTextEditingController(text: text);
        controller.applyFormatAction(
          'text:direction:rtl',
          range: FormatRange(start: 0, end: text.length),
          baseFontSize: 14,
        );
        final api = infoSpansForApi(controller.spans, text);
        final restored = SpanTextEditingController(
          text: text,
          spans: infoSpansToCombined(api.body, text, titleSpans: api.title),
        );
        expect(
          restored.directionOverride,
          TextDirection.rtl,
          reason: 'info $text',
        );
        final cell = DocumentTableCell.fromJson({
          'text': text,
          'spans': controller.spans,
        });
        final table = SpanTextEditingController(
          text: text,
          spans: cell.toJson()['spans'],
        );
        expect(
          table.directionOverride,
          TextDirection.rtl,
          reason: 'table $text',
        );
        table.dispose();
        restored.dispose();
        controller.dispose();
      }
    },
  );
  testWidgets('preview hides direction syntax', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReadOnlyDocumentView(
          blocks: parseAgentTextBlocks(
            '[DIR rtl]hello\n\n[DIR ltr]# שלום\n\n[DIR rtl]',
          ),
        ),
      ),
    );
    expect(find.textContaining('[DIR'), findsNothing);
    expect(find.text('hello'), findsOneWidget);
    expect(find.text('שלום'), findsOneWidget);
  });
}
