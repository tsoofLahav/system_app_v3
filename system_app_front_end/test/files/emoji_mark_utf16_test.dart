import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:system_app_front_end/areas/files/editor/super_editor_mark.dart';
import 'package:system_app_front_end/areas/files/rich_text/text_formatting.dart';

void main() {
  test('snapDocumentSelection expands a mark that splits an emoji', () {
    const text = 'a😀b';
    final doc = MutableDocument(
      nodes: [ParagraphNode(id: 'p1', text: AttributedText(text))],
    );
    final emojiStart = text.indexOf('😀');
    final split = DocumentSelection(
      base: DocumentPosition(
        nodeId: 'p1',
        nodePosition: TextNodePosition(offset: emojiStart),
      ),
      extent: DocumentPosition(
        nodeId: 'p1',
        nodePosition: TextNodePosition(offset: emojiStart + 1),
      ),
    );

    final snapped = snapDocumentSelection(doc, split);
    expect(
      (snapped.base.nodePosition as TextNodePosition).offset,
      emojiStart,
    );
    expect(
      (snapped.extent.nodePosition as TextNodePosition).offset,
      emojiStart + '😀'.length,
    );
  });

  test('TextSpanBuilder can paint a span that used to split an emoji', () {
    const text = 'a😀b';
    final emojiStart = text.indexOf('😀');
    final span = TextSpanBuilder.build(
      text: text,
      baseStyle: const TextStyle(),
      spans: [
        {'start': emojiStart, 'end': emojiStart + 1, 'bold': true},
      ],
    );
    expect(() => span.toPlainText(), returnsNormally);
    expect(span.toPlainText(), text);
  });
}
