import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/features/document/document_codec.dart';
import 'package:system_app_front_end/features/document/document_model.dart';

void main() {
  test('empty document is v3', () {
    final doc = DocumentCodec.parse('');
    expect(doc.version, RichDocument.documentVersion);
    expect(doc.blocks, isEmpty);
  });

  test('paragraph round trip', () {
    final body = DocumentCodec.serialize(
      RichDocument(
        version: 3,
        blocks: [
          ParagraphNode(id: 'b1', text: 'Hello', spans: [
            TextSpanMark(start: 0, end: 5, bold: true),
          ]),
        ],
      ),
    );
    final doc = DocumentCodec.parse(body);
    expect(doc.blocks.first, isA<ParagraphNode>());
    expect((doc.blocks.first as ParagraphNode).text, 'Hello');
  });

  test('embed block round trip', () {
    final body = DocumentCodec.serialize(
      RichDocument(
        version: 3,
        blocks: [
          ParagraphNode(id: 'b1', text: 'Before'),
          EmbedNode(id: 'b2', objectId: 42),
          ParagraphNode(id: 'b3', text: 'After'),
        ],
      ),
    );
    final parsed = jsonDecode(body) as Map<String, dynamic>;
    expect(parsed['version'], 3);
    expect(parsed['blocks'], hasLength(3));
    final doc = DocumentCodec.parse(body);
    expect(doc.blocks[1], isA<EmbedNode>());
    expect((doc.blocks[1] as EmbedNode).objectId, 42);
  });

  test('insert embed block', () {
    final doc = DocumentCodec.insertEmbedBlock(
      DocumentCodec.empty(),
      7,
      blockIndex: 0,
    );
    expect(doc.blocks.single, isA<EmbedNode>());
  });

  test('migrate v2 inline body', () {
    final body = jsonEncode({
      'version': 2,
      'text': 'Title\uFFFC',
      'spans': [],
      'regions': [],
      'embeds': [
        {
          'id': 'e1',
          'kind': 'object',
          'object_type': 'task_list',
          'object_id': 9,
          'offset': 5,
        },
      ],
    });
    final doc = DocumentCodec.parse(body);
    expect(doc.blocks.first, isA<ParagraphNode>());
    expect(doc.blocks[1], isA<EmbedNode>());
  });
}
