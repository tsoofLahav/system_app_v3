import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/model/document_buffer.dart';
import 'package:system_app_front_end/areas/files/model/document_codec.dart';
import 'package:system_app_front_end/areas/files/model/document_model.dart';
import 'package:system_app_front_end/areas/files/model/document_text_codec.dart';

void main() {
  test('empty document parses to empty view', () {
    final doc = DocumentCodec.parse('');
    expect(doc.version, RichDocument.documentVersion);
    expect(doc.blocks, isEmpty);
  });

  test('paragraph round trip via v4 marker text', () {
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
    expect(body, startsWith(DocumentTextCodec.header));
    final doc = DocumentCodec.parse(body);
    expect(doc.blocks.first, isA<ParagraphNode>());
    expect((doc.blocks.first as ParagraphNode).text, 'Hello');
  });

  test('embed pointer round trip', () {
    final body = DocumentCodec.serialize(
      RichDocument(
        version: 3,
        blocks: [
          ParagraphNode(id: 'b1', text: 'Before'),
          EmbedNode(id: 'b2', objectId: 42, objectType: 'info'),
          ParagraphNode(id: 'b3', text: 'After'),
        ],
      ),
      objectTypes: {42: 'info'},
    );
    expect(body, contains('[INFO id="42"]'));
    final doc = DocumentCodec.parse(body);
    expect(doc.blocks, hasLength(3));
    expect(doc.blocks[1], isA<EmbedNode>());
    expect((doc.blocks[1] as EmbedNode).objectId, 42);
  });

  test('insert embed pointer via buffer', () {
    final buf = DocumentBuffer.empty();
    buf.insertPointer(objectId: 7, objectType: 'info', gapIndex: 0);
    final doc = buf.toRichDocument();
    expect(doc.blocks.whereType<EmbedNode>().single.objectId, 7);
  });

  test('list block types round trip', () {
    final bullet = DocumentCodec.serialize(
      RichDocument(
        version: 3,
        blocks: [
          ListNode(
            id: 'b1',
            items: [ListItem(id: 'li1', text: 'Item')],
          ),
        ],
      ),
    );
    final bulletDoc = DocumentCodec.parse(bullet);
    expect(bulletDoc.blocks.first, isA<ListNode>());
    expect((bulletDoc.blocks.first as ListNode).type, 'bullet_list');

    final ordered = DocumentCodec.serialize(
      RichDocument(
        version: 3,
        blocks: [
          ListNode(
            id: 'b2',
            listStyle: 'numbered',
            items: [ListItem(id: 'li2', text: 'Step')],
          ),
        ],
      ),
    );
    final orderedDoc = DocumentCodec.parse(ordered);
    expect((orderedDoc.blocks.first as ListNode).type, 'ordered_list');
  });

  test('spans are dropped on v4 serialize (until span encoding)', () {
    final body = DocumentCodec.serialize(
      RichDocument(
        version: 3,
        blocks: [
          ParagraphNode(
            id: 'b1',
            text: 'Red',
            spans: [TextSpanMark(start: 0, end: 3, color: '#E53935')],
          ),
        ],
      ),
    );
    final doc = DocumentCodec.parse(body);
    final block = doc.blocks.first as ParagraphNode;
    expect(block.text, 'Red');
    expect(block.spans, isEmpty);
  });

  test('coalesce adjacent paragraphs', () {
    final doc = DocumentCodec.coalesceAdjacentParagraphs(
      RichDocument(
        version: 3,
        blocks: [
          ParagraphNode(id: 'b1', text: 'Line one'),
          ParagraphNode(id: 'b2', text: 'Line two'),
          ListNode(
            id: 'b3',
            items: [ListItem(id: 'li1', text: 'Item')],
          ),
        ],
      ),
    );
    expect(doc.blocks, hasLength(2));
    expect(doc.blocks.first, isA<ParagraphNode>());
    expect((doc.blocks.first as ParagraphNode).text, 'Line one\nLine two');
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
