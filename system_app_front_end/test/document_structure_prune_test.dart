import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/editor/document_structure_prune.dart';
import 'package:system_app_front_end/areas/files/editor/document_text_flow.dart';
import 'package:system_app_front_end/areas/files/model/document_model.dart';

ListNode _list(String id, int items) => ListNode(
      id: id,
      items: [
        for (var i = 0; i < items; i++) ListItem(id: '$id-li$i', text: 'point $i'),
      ],
    );

TableNode _table(String id, int rows, int columns) => TableNode(
      id: id,
      rows: [
        for (var r = 0; r < rows; r++)
          [
            for (var c = 0; c < columns; c++) DocumentTableCell(text: 'r${r}c$c'),
          ],
      ],
    );

Set<String> _wholeRow(String id, int row, int columns) => {
      for (var c = 0; c < columns; c++) tableCellSegmentId(id, row, c),
    };

Set<String> _wholeTable(String id, int rows, int columns) => {
      for (var r = 0; r < rows; r++) ..._wholeRow(id, r, columns),
    };

void main() {
  group('marking whole points in a list', () {
    test('a fully marked point is removed, the rest of the list stays', () {
      final result = pruneFullyMarkedStructures(
        blocks: [_list('b1', 3)],
        fullyEmptied: {listItemSegmentId('b1', 1)},
        spansParts: true,
      );

      expect(result.changed, isTrue);
      final list = result.blocks.single as ListNode;
      expect(list.items.map((i) => i.id), ['b1-li0', 'b1-li2']);
    });

    test('marking every point removes the whole list', () {
      final result = pruneFullyMarkedStructures(
        blocks: [_list('b1', 3), ParagraphNode(id: 'b2', text: 'after')],
        fullyEmptied: {
          for (var i = 0; i < 3; i++) listItemSegmentId('b1', i),
        },
        spansParts: true,
      );

      expect(result.blocks.map((b) => b.id), ['b2']);
      expect(result.firstRemovedIndex, 0);
    });

    test('a point marked only in part survives', () {
      final result = pruneFullyMarkedStructures(
        blocks: [_list('b1', 3)],
        fullyEmptied: const {},
        spansParts: true,
      );

      expect(result.changed, isFalse);
      expect((result.blocks.single as ListNode).items, hasLength(3));
    });
  });

  group('marking whole rows in a table', () {
    test('a fully marked row is removed, the other rows stay', () {
      final result = pruneFullyMarkedStructures(
        blocks: [_table('b1', 3, 2)],
        fullyEmptied: _wholeRow('b1', 1, 2),
        spansParts: true,
      );

      final table = result.blocks.single as TableNode;
      expect(table.rows, hasLength(2));
      expect(table.rows.map((r) => r.first.text), ['r0c0', 'r2c0']);
    });

    test('a row with only some cells marked survives', () {
      final result = pruneFullyMarkedStructures(
        blocks: [_table('b1', 2, 3)],
        // Two of the three cells — not the whole row.
        fullyEmptied: {
          tableCellSegmentId('b1', 0, 0),
          tableCellSegmentId('b1', 0, 1),
        },
        spansParts: true,
      );

      expect(result.changed, isFalse);
      expect((result.blocks.single as TableNode).rows, hasLength(2));
    });

    test('marking every row removes the whole table', () {
      final result = pruneFullyMarkedStructures(
        blocks: [ParagraphNode(id: 'b0', text: 'before'), _table('b1', 2, 2)],
        fullyEmptied: _wholeTable('b1', 2, 2),
        spansParts: true,
      );

      expect(result.blocks.map((b) => b.id), ['b0']);
    });
  });

  group('paragraphs', () {
    test('a paragraph swallowed by a marking that crosses parts is removed', () {
      final result = pruneFullyMarkedStructures(
        blocks: [
          ParagraphNode(id: 'b0', text: 'first'),
          ParagraphNode(id: 'b1', text: 'middle'),
          ParagraphNode(id: 'b2', text: 'last'),
        ],
        fullyEmptied: {paragraphSegmentId('b1')},
        spansParts: true,
      );

      expect(result.blocks.map((b) => b.id), ['b0', 'b2']);
    });

    test('a paragraph marked on its own only becomes empty', () {
      final result = pruneFullyMarkedStructures(
        blocks: [ParagraphNode(id: 'b0', text: 'only')],
        fullyEmptied: {paragraphSegmentId('b0')},
        spansParts: false,
      );

      expect(result.changed, isFalse);
      expect(result.blocks.map((b) => b.id), ['b0']);
    });
  });

  test('a file emptied completely keeps one paragraph to type in', () {
    final result = pruneFullyMarkedStructures(
      blocks: [_list('b1', 2), _table('b2', 1, 2)],
      fullyEmptied: {
        listItemSegmentId('b1', 0),
        listItemSegmentId('b1', 1),
        ..._wholeRow('b2', 0, 2),
      },
      spansParts: true,
    );

    expect(result.blocks, hasLength(1));
    expect(result.blocks.single, isA<ParagraphNode>());
  });

  test('nothing marked in full leaves the document untouched', () {
    final blocks = [_list('b1', 2), _table('b2', 2, 2)];
    final result = pruneFullyMarkedStructures(
      blocks: blocks,
      fullyEmptied: const {},
      spansParts: true,
    );

    expect(result.changed, isFalse);
    expect(result.blocks, same(blocks));
  });
}
