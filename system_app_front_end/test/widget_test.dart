import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/features/document/document_codec.dart';
import 'package:system_app_front_end/features/document/inline_document_model.dart';

void main() {
  test('migrates legacy info marker to object embed', () {
    const body = 'Hello\n{{info:3}}\nWorld';
    final doc = DocumentCodec.parse(body);
    expect(doc.embeds.length, 1);
    expect(doc.embeds.first.objectId, 3);
    expect(doc.embeds.first.objectType, 'info');
  });

  test('serializes inline document with spans', () {
    final json = DocumentCodec.serialize(
      const InlineDocument(
        version: 2,
        text: 'Hi',
        spans: [TextSpanMark(start: 0, end: 2, bold: true)],
      ),
    );
    expect(json, contains('"bold":true'));
    expect(json, contains('"version":2'));
  });

  test('insertEmbed shifts later offsets', () {
    const doc = InlineDocument(version: 2, text: 'abc');
    final withEmbed = DocumentCodec.insertEmbed(
      doc,
      const DocumentEmbed(id: 'e1', kind: 'graph', offset: 1),
      offset: 1,
    );
    expect(withEmbed.text.length, 4);
    expect(withEmbed.embeds.single.offset, 1);
  });

  test('moveEmbed relocates slot', () {
    var doc = DocumentCodec.insertEmbed(
      const InlineDocument(version: 2, text: 'abcd'),
      const DocumentEmbed(id: 'e1', kind: 'image', offset: 1, url: ''),
      offset: 1,
    );
    doc = DocumentCodec.moveEmbed(doc, 'e1', 3);
    expect(doc.embeds.single.offset, 3);
    expect(doc.text.replaceAll(InlineDocument.embedChar, '').length, 4);
  });

  test('normalize inserts embed chars on serialize', () {
    const doc = InlineDocument(
      version: 2,
      text: 'ab',
      embeds: [
        DocumentEmbed(id: 'e1', kind: 'image', offset: 1, url: 'http://x'),
      ],
    );
    final json = DocumentCodec.serialize(doc);
    final parsed = jsonDecode(json) as Map<String, dynamic>;
    expect(parsed['text'], contains(InlineDocument.embedChar));
  });

  test('rebuildFromText shifts list region bounds on edit', () {
    const base = InlineDocument(
      version: 2,
      text: '• a\n• b',
      regions: [
        DocumentRegion(
          id: 'r1',
          kind: 'list',
          start: 0,
          end: 7,
          listStyle: 'bullet',
        ),
      ],
    );
    final rebuilt = DocumentCodec.rebuildFromText(
      base: base,
      newText: '• aa\n• bb',
      newSpans: const [],
      newEmbeds: const [],
    );
    expect(rebuilt.regions.single.end, greaterThan(base.regions.single.end));
  });
}
