import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/features/document/document_codec.dart';
import 'package:system_app_front_end/features/document/document_model.dart';

void main() {
  test('migrates legacy info marker to object node', () {
    const body = 'Hello\n{{info:3}}\nWorld';
    final doc = DocumentCodec.parse(body);
    expect(doc.nodes.length, 3);
    expect(doc.nodes[1], isA<ObjectNode>());
    expect((doc.nodes[1] as ObjectNode).objectId, 3);
  });

  test('serializes paragraph with spans', () {
    final json = DocumentCodec.serialize(
      RichDocument(
        version: 1,
        nodes: [
          ParagraphNode(
            id: 'n1',
            text: 'Hi',
            spans: [TextSpanMark(start: 0, end: 2, bold: true)],
          ),
        ],
      ),
    );
    expect(json, contains('"bold":true'));
  });
}
