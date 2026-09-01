import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/model/document_codec.dart';
import 'package:system_app_front_end/areas/files/model/document_model.dart';
import 'package:system_app_front_end/areas/files/model/document_text_codec.dart';

void main() {
  group('DocumentTextCodec', () {
    test('serialize embeds as pointer-only lines', () {
      final doc = RichDocument(
        version: 3,
        blocks: [
          ParagraphNode(id: 'a', text: 'Hello'),
          EmbedNode(id: 'e', objectId: 42, objectType: 'info'),
          ParagraphNode(id: 'b', text: 'World'),
        ],
      );
      final text = DocumentTextCodec.serialize(doc);
      expect(text, startsWith(DocumentTextCodec.header));
      expect(text, contains('[INFO id="42"]'));
      expect(text, isNot(contains('[/INFO]')));
    });

    test('parse pointer lines back to embeds', () {
      final doc = DocumentTextCodec.parse(
        '${DocumentTextCodec.header}\nHello\n\n[INFO id="9"]\n\nWorld',
      );
      expect(doc.blocks, hasLength(3));
      expect(doc.blocks[1], isA<EmbedNode>());
      expect((doc.blocks[1] as EmbedNode).objectId, 9);
      expect((doc.blocks[1] as EmbedNode).objectType, 'info');
    });

    test('movePointerInText reorders without splitting neighbors', () {
      final moved = DocumentTextCodec.movePointerInText(
        '${DocumentTextCodec.header}\nHello\n\n[INFO id="9"]\n\nWorld',
        objectId: 9,
        gapIndex: 0,
      );
      final body = DocumentTextCodec.stripHeader(moved);
      expect(body.startsWith('[INFO id="9"]'), isTrue);
      expect(body, contains('Hello'));
      expect(body, contains('World'));
    });

    test('DocumentCodec.parse/serialize use v4 text', () {
      final doc = DocumentCodec.parse(
        '${DocumentTextCodec.header}\nHi\n\n[TASK_LIST id="3"]',
      );
      final out = DocumentCodec.serialize(
        doc,
        objectTypes: {3: 'task_list'},
      );
      expect(out, startsWith(DocumentTextCodec.header));
      expect(out, contains('[TASK_LIST id="3"]'));
    });

    test('table pointer round-trips', () {
      final doc = DocumentTextCodec.parse(
        '${DocumentTextCodec.header}\n[TABLE id="11"]\n\nAfter',
      );
      expect(doc.blocks.first, isA<EmbedNode>());
      expect((doc.blocks.first as EmbedNode).objectType, 'table');
      final out = DocumentTextCodec.serialize(
        doc,
        objectTypes: {11: 'table'},
      );
      expect(out, contains('[TABLE id="11"]'));
    });
  });
}
