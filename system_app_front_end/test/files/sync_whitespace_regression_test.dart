import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:system_app_front_end/areas/files/model/marker_super_editor_bridge.dart';
import 'package:system_app_front_end/areas/files/editor/document_three_way.dart';
import 'package:system_app_front_end/areas/files/model/document_text_codec.dart';

void main() {
  for (final text in [
    '  hello  ',
    'a\n\n',
    '\n\na',
    'a\n\n\n\nb',
    '\n\n',
    'hello\n\nworld',
    '\nhello\n',
    '   ',
    'שלום 123\n\nEnglish',
  ]) {
    test('save and reload preserve paragraph ${text.codeUnits}', () {
      final source = MutableDocument(
        nodes: [ParagraphNode(id: 'p', text: AttributedText(text))],
      );
      final loaded = markerTextToMutableDocument(
        mutableDocumentToMarkerText(source),
      );
      final actual = [
        for (var i = 0; i < loaded.nodeCount; i++)
          (loaded.getNodeAt(i) as ParagraphNode).text.toPlainText(),
      ].join('\n');
      expect(actual, text);
    });
  }

  test('leading user blank paragraph survives save and reload', () {
    final source = MutableDocument(
      nodes: [
        ParagraphNode(id: 'blank', text: AttributedText()),
        ParagraphNode(id: 'text', text: AttributedText('hello')),
      ],
    );
    final loaded = markerTextToMutableDocument(
      mutableDocumentToMarkerText(source),
    );
    expect(loaded.nodeCount, 2);
    expect((loaded.getNodeAt(0) as ParagraphNode).text.toPlainText(), '');
  });

  test('concurrent edit plus end insertion is not duplicated by merge', () {
    final result = threeWayMarkerText(
      base: DocumentTextCodec.wrap('a'),
      local: DocumentTextCodec.wrap('A'),
      server: DocumentTextCodec.wrap('a\n\nb'),
    );
    expect(result.hasConflicts, false);
    expect(result.merged, DocumentTextCodec.wrap('A\n\nb'));
  });
}
