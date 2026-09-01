import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/editor/document_session.dart';
import 'package:system_app_front_end/areas/files/editor/document_text_flow.dart';
import 'package:system_app_front_end/areas/files/model/document_codec.dart';
import 'package:system_app_front_end/areas/files/model/document_model.dart';

RichDocument _doc(List<DocumentNode> blocks) => RichDocument(
      version: RichDocument.documentVersion,
      blocks: blocks,
    );

void main() {
  const session = DocumentSession();

  group('coalesceAdjacentParagraphs', () {
    test('drops newline-only and empty stubs next to embeds', () {
      final doc = _doc([
        ParagraphNode(id: 'a', text: 'keep'),
        ParagraphNode(id: 'blank', text: '\n'),
        EmbedNode(id: 'e', objectId: 1),
        ParagraphNode(id: 'trail', text: '  '),
      ]);

      final coalesced = DocumentCodec.coalesceAdjacentParagraphs(doc);

      expect(coalesced.blocks.map((b) => b.id).toList(), ['a', 'e']);
      expect((coalesced.blocks.first as ParagraphNode).text, 'keep');
    });

    test('drops empty paragraph pressed against an embed before it', () {
      final doc = _doc([
        ParagraphNode(id: 'empty', text: ''),
        EmbedNode(id: 'e', objectId: 1),
        ParagraphNode(id: 'a', text: 'after'),
      ]);

      final coalesced = DocumentCodec.coalesceAdjacentParagraphs(doc);

      expect(coalesced.blocks.map((b) => b.id).toList(), ['e', 'a']);
    });
  });

  group('deleteEmbedBlock', () {
    test('removes embed and coalesces paragraphs on both sides', () {
      final doc = _doc([
        ParagraphNode(id: 'a', text: 'hello'),
        EmbedNode(id: 'e', objectId: 9),
        ParagraphNode(id: 'b', text: 'world'),
      ]);

      final result = session.deleteEmbedBlock(doc, 'e');

      expect(result.changed, isTrue);
      expect(result.removedObjectId, 9);
      expect(result.doc.blocks, hasLength(1));
      final p = result.doc.blocks.single as ParagraphNode;
      expect(p.text, 'hello\nworld');
    });

    test('drops empty paragraph stubs instead of blank gaps', () {
      final doc = _doc([
        ParagraphNode(id: 'a', text: 'keep'),
        EmbedNode(id: 'e', objectId: 1),
        ParagraphNode(id: 'empty', text: ''),
      ]);

      final result = session.deleteEmbedBlock(doc, 'e');

      expect(result.doc.blocks, hasLength(1));
      expect((result.doc.blocks.single as ParagraphNode).text, 'keep');
    });

    test('lands caret at end of paragraph above', () {
      final doc = _doc([
        ParagraphNode(id: 'a', text: 'hello'),
        EmbedNode(id: 'e', objectId: 9),
        ParagraphNode(id: 'b', text: 'world'),
      ]);

      final result = session.deleteEmbedBlock(doc, 'e');

      expect(result.focusSegmentId, paragraphSegmentId('a'));
      expect(result.focusOffset, 'hello'.length);
      expect(result.landingBlockId, 'a');
    });
  });

  group('exitListBelow / removeStructureBlock', () {
    test('exit list on last empty item becomes a paragraph', () {
      final doc = _doc([
        ListNode(
          id: 'l',
          items: [ListItem(id: 'li0', text: '')],
        ),
      ]);

      final result = session.exitListBelow(doc, 'l', 0);

      expect(result.changed, isTrue);
      expect(result.doc.blocks.single, isA<ParagraphNode>());
      expect(result.focusSegmentId, paragraphSegmentId(result.landingBlockId!));
    });

    test('removeStructureBlock coalesces surrounding text and lands at end above',
        () {
      final doc = _doc([
        ParagraphNode(id: 'a', text: 'before'),
        ListNode(
          id: 'l',
          items: [ListItem(id: 'li0', text: '')],
        ),
        ParagraphNode(id: 'b', text: 'after'),
      ]);

      final result = session.removeStructureBlock(doc, 'l');

      expect(result.doc.blocks, hasLength(1));
      expect((result.doc.blocks.single as ParagraphNode).text, 'before\nafter');
      expect(result.focusSegmentId, paragraphSegmentId('a'));
      expect(result.focusOffset, 'before'.length);
    });
  });

  group('prepareInsertSite', () {
    test('mid-paragraph split returns gap between halves', () {
      final doc = _doc([
        ParagraphNode(id: 'p', text: 'abcdef'),
      ]);

      final result = session.prepareInsertSite(
        doc: doc,
        focusedSegmentId: 'p',
        fallbackBlockIndex: 0,
        liveTextOf: (_) => 'abcdef',
        liveSpansOf: (_) => null,
        caretOffsetOf: (_) => 3,
      );

      expect(result.changed, isTrue);
      expect(result.insertGapIndex, 1);
      expect(result.doc.blocks, hasLength(2));
      expect((result.doc.blocks[0] as ParagraphNode).text, 'abc');
      expect((result.doc.blocks[1] as ParagraphNode).text, 'def');
    });
  });
}
