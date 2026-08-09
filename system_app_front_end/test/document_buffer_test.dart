import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/model/document_buffer.dart';
import 'package:system_app_front_end/areas/files/model/document_text_codec.dart';

void main() {
  group('DocumentBuffer', () {
    test('indexes paragraphs and pointer embeds', () {
      final buf = DocumentBuffer(
        'Hello\nworld\n\n[INFO id="42"]\n\nAfter',
      );
      expect(buf.parts, hasLength(3));
      expect(buf.parts[0].kind, DocPartKind.paragraph);
      expect(buf.parts[0].slice(buf.text), 'Hello\nworld');
      expect(buf.parts[1].kind, DocPartKind.embed);
      expect(buf.parts[1].objectId, 42);
      expect(buf.parts[1].key, 'embed:42');
      expect(buf.parts[2].slice(buf.text), 'After');
    });

    test('replacePartSlice updates text and reindexes', () {
      final buf = DocumentBuffer('Hello\n\n[INFO id="1"]');
      final key = buf.parts.first.key;
      expect(buf.replacePartSlice(key, 'Hi there'), isTrue);
      expect(buf.text, startsWith('Hi there'));
      expect(buf.parts.any((p) => p.objectId == 1), isTrue);
    });

    test('movePointer cut/pastes without leaving blank at origin', () {
      final buf = DocumentBuffer('Hello\n\n[INFO id="9"]\n\nWorld');
      expect(buf.movePointer(9, 0), isTrue);
      expect(buf.parts.first.kind, DocPartKind.embed);
      expect(buf.parts[1].slice(buf.text), 'Hello');
      expect(buf.parts[2].slice(buf.text), 'World');
      expect(buf.text.contains('\n\n\n'), isFalse);
    });

    test('splitPartAndInsertPointer trims line breaks', () {
      final buf = DocumentBuffer('hello\nworld\n\n[INFO id="2"]');
      final para = buf.parts.first;
      expect(
        buf.splitPartAndInsertPointer(
          partKey: para.key,
          cut: 6, // after "hello\n"
          objectId: 2,
          objectType: 'info',
        ),
        isTrue,
      );
      expect(buf.parts, hasLength(3));
      expect(buf.parts[0].slice(buf.text), 'hello');
      expect(buf.parts[1].objectId, 2);
      expect(buf.parts[2].slice(buf.text), 'world');
    });

    test('drops blank neighbor next to embed on reindex', () {
      final buf = DocumentBuffer('Keep\n\n[SPACER n="1"]\n\n[INFO id="3"]');
      expect(buf.parts.where((p) => p.kind == DocPartKind.embed), hasLength(1));
      expect(buf.parts.where((p) => p.kind == DocPartKind.spacer), isEmpty);
      expect(
        buf.parts.where((p) => p.kind == DocPartKind.paragraph),
        hasLength(1),
      );
      expect(buf.parts.first.slice(buf.text).trim(), 'Keep');
    });

    test('fromStored strips v4 header', () {
      final buf = DocumentBuffer.fromStored(
        '${DocumentTextCodec.header}\nNotes\n\n[TASK_LIST id="7"]',
      );
      expect(buf.text, isNot(contains(DocumentTextCodec.header)));
      expect(buf.stored, startsWith(DocumentTextCodec.header));
      expect(buf.parts.last.objectId, 7);
    });

    test('localToGlobal / globalToLocal', () {
      final buf = DocumentBuffer('ab\n\n[INFO id="1"]');
      final key = buf.parts.first.key;
      expect(buf.localToGlobal(key, 1), 1);
      expect(buf.globalToLocal(key, 1), 1);
    });
  });
}
