import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:system_app_front_end/areas/files/model/document_text_codec.dart';
import 'package:system_app_front_end/areas/files/model/marker_super_editor_bridge.dart';
import 'package:system_app_front_end/areas/files/model/object_embed_node.dart';

void main() {
  group('marker_super_editor_bridge', () {
    test('round-trips paragraphs and info pointer', () {
      final stored =
          '${DocumentTextCodec.header}\nHello\n\n[INFO id="42"]\n\nWorld';
      final doc = markerTextToMutableDocument(stored);
      expect(doc.nodeCount, 3);
      expect(doc.getNodeAt(0), isA<ParagraphNode>());
      expect((doc.getNodeAt(0) as ParagraphNode).text.toPlainText(), 'Hello');
      expect(doc.getNodeAt(1), isA<ObjectEmbedNode>());
      final embed = doc.getNodeAt(1) as ObjectEmbedNode;
      expect(embed.objectId, 42);
      expect(embed.objectType, 'info');
      expect(embed.id, 'embed:42');
      expect(doc.getNodeAt(2), isA<ParagraphNode>());

      final out = mutableDocumentToMarkerText(doc);
      expect(out, startsWith(DocumentTextCodec.header));
      expect(out, contains('Hello'));
      expect(out, contains('[INFO id="42"]'));
      expect(out, contains('World'));
      expect(out, isNot(contains('[/INFO]')));
    });

    test('round-trips bullet list fence via ListItemNodes', () {
      final stored = '''
${DocumentTextCodec.header}
Intro

[BULLET_LIST]
- one
- two
[/BULLET_LIST]

Outro''';
      final doc = markerTextToMutableDocument(stored);
      expect(doc.getNodeAt(0), isA<ParagraphNode>());
      expect(doc.getNodeAt(1), isA<ListItemNode>());
      expect(doc.getNodeAt(2), isA<ListItemNode>());
      expect(doc.getNodeAt(3), isA<ParagraphNode>());

      final out = mutableDocumentToMarkerText(doc);
      expect(out, contains('[BULLET_LIST]'));
      expect(out, contains('- one'));
      expect(out, contains('- two'));
      expect(out, contains('[/BULLET_LIST]'));
      expect(out, contains('Intro'));
      expect(out, contains('Outro'));
    });

    test('loads table pointer as ObjectEmbedNode', () {
      final stored =
          '${DocumentTextCodec.header}\n[TABLE id="9"]\n\nAfter';
      final doc = markerTextToMutableDocument(stored);
      expect(doc.getNodeAt(0), isA<ObjectEmbedNode>());
      final embed = doc.getNodeAt(0) as ObjectEmbedNode;
      expect(embed.objectType, 'table');
      expect(embed.objectId, 9);
    });

    test('loads legacy table fence as LegacyTableFenceNode', () {
      final stored =
          '${DocumentTextCodec.header}\n[TABLE]\nA\tB\n1\t2\n[/TABLE]';
      final doc = markerTextToMutableDocument(stored);
      expect(doc.getNodeAt(0), isA<LegacyTableFenceNode>());
      expect(documentHasLegacyTableFences(doc), isTrue);
      final fence = doc.getNodeAt(0) as LegacyTableFenceNode;
      expect(fence.rows.first, ['A', 'B']);
    });

    test('markerGapIndexForNodeIndex collapses list items', () {
      final doc = MutableDocument(
        nodes: [
          ParagraphNode(id: 'p', text: AttributedText('Hi')),
          ListItemNode.unordered(id: 'l1', text: AttributedText('a')),
          ListItemNode.unordered(id: 'l2', text: AttributedText('b')),
          ParagraphNode(id: 'q', text: AttributedText('Bye')),
        ],
      );
      expect(markerGapIndexForNodeIndex(doc, 0), 0);
      expect(markerGapIndexForNodeIndex(doc, 1), 1); // before list fence
      expect(markerGapIndexForNodeIndex(doc, 3), 2); // after list (= before Bye)
      expect(markerGapIndexForNodeIndex(doc, 4), 3); // end
    });

    test('prunes empty neighbors around embeds on save', () {
      final doc = MutableDocument(
        nodes: [
          ParagraphNode(id: 'a', text: AttributedText('Hi')),
          ParagraphNode(id: 'empty', text: AttributedText()),
          ObjectEmbedNode(
            id: ObjectEmbedNode.idFor(1),
            objectId: 1,
            objectType: 'info',
          ),
          ParagraphNode(id: 'empty2', text: AttributedText()),
          ParagraphNode(id: 'b', text: AttributedText('Bye')),
        ],
      );
      final out = mutableDocumentToMarkerText(doc);
      final body = DocumentTextCodec.stripHeader(out);
      expect(body, isNot(contains('[SPACER')));
      expect(body, contains('[INFO id="1"]'));
      expect(body, contains('Hi'));
      expect(body, contains('Bye'));
    });
  });
}
