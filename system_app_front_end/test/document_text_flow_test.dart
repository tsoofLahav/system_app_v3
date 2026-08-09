import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/editor/document_text_flow.dart';

/// Builds a flow whose segments are attached with the given texts, in order.
DocumentTextFlow _flowWith(Map<String, String> segments) {
  final flow = DocumentTextFlow()..setOrder(segments.keys.toList());
  segments.forEach((id, text) {
    flow.register(id, TextEditingController(text: text), FocusNode());
  });
  return flow;
}

void main() {
  group('segment ids', () {
    test('encode paragraph, list item and table cell distinctly', () {
      expect(paragraphSegmentId('b1'), 'b1');
      expect(listItemSegmentId('b2', 3), 'b2#i3');
      expect(tableCellSegmentId('b3', 1, 2), 'b3#c1:2');
      expect(listItemSegmentId('b2', 3), isNot(tableCellSegmentId('b2', 3, 0)));
    });
  });

  group('navigation across parts', () {
    test('left at offset 0 crosses into the end of the previous segment', () {
      final flow = _flowWith({'a': 'one', 'b': 'two'});

      final target = flow.positionBefore(const DocumentTextPosition('b', 0));

      expect(target, const DocumentTextPosition('a', 3));
    });

    test('right at the end crosses into the start of the next segment', () {
      final flow = _flowWith({'a': 'one', 'b': 'two'});

      final target = flow.positionAfter(const DocumentTextPosition('a', 3));

      expect(target, const DocumentTextPosition('b', 0));
    });

    test('stays inside the segment when not at a boundary', () {
      final flow = _flowWith({'a': 'one', 'b': 'two'});

      expect(
        flow.positionBefore(const DocumentTextPosition('a', 2)),
        const DocumentTextPosition('a', 1),
      );
      expect(
        flow.positionAfter(const DocumentTextPosition('a', 1)),
        const DocumentTextPosition('a', 2),
      );
    });

    test('returns null at the document edges', () {
      final flow = _flowWith({'a': 'one', 'b': 'two'});

      expect(flow.positionBefore(const DocumentTextPosition('a', 0)), isNull);
      expect(flow.positionAfter(const DocumentTextPosition('b', 3)), isNull);
    });

    test('vertical movement keeps the column where the target is long enough', () {
      final flow = _flowWith({'a': 'a long line', 'b': 'hi'});

      expect(
        flow.positionAbove(const DocumentTextPosition('b', 1),
            preferredOffset: 5),
        const DocumentTextPosition('a', 5),
      );
      // Clamped: target is shorter than the preferred column.
      expect(
        flow.positionBelow(const DocumentTextPosition('a', 0),
            preferredOffset: 9),
        const DocumentTextPosition('b', 2),
      );
    });

    test('walks a paragraph into a list bullet and then a table cell', () {
      final flow = _flowWith({
        paragraphSegmentId('b1'): 'intro',
        listItemSegmentId('b2', 0): 'first',
        listItemSegmentId('b2', 1): 'second',
        tableCellSegmentId('b3', 0, 0): 'cell',
      });

      var position = const DocumentTextPosition('b1', 5);
      position = flow.positionAfter(position)!;
      expect(position.segmentId, 'b2#i0');
      position = flow.positionAbove(position)!;
      expect(position.segmentId, 'b1');

      position = flow.positionBelow(const DocumentTextPosition('b2#i1', 0))!;
      expect(position.segmentId, 'b3#c0:0');
    });
  });

  group('deleting whole parts reports them for removal', () {
    test('a part marked end to end is reported as fully marked', () {
      final flow = _flowWith({'a': 'alpha', 'b': 'beta', 'c': 'gamma'});
      flow.collapseTo(const DocumentTextPosition('a', 2));
      flow.extendTo(const DocumentTextPosition('c', 3));

      // Only the middle part is covered end to end.
      expect(flow.fullyMarkedSegments(), {'b'});
    });

    test('every part of a fully marked run is reported', () {
      final flow = _flowWith({'a': 'alpha', 'b': 'beta', 'c': 'gamma'});
      flow.selectAll();

      expect(flow.fullyMarkedSegments(), {'a', 'b', 'c'});
    });

    test('an already empty part is not reported', () {
      final flow = _flowWith({'a': 'alpha', 'b': '', 'c': 'gamma'});
      flow.selectAll();

      expect(flow.fullyMarkedSegments(), {'a', 'c'});
    });

    test('delete hands the fully marked parts to the editor', () {
      final flow = _flowWith({'a': 'alpha', 'b': 'beta', 'c': 'gamma'});
      Set<String>? pruned;
      var sawSpansParts = false;
      flow.onPruneStructures = (ids, {required spansParts}) {
        pruned = ids;
        sawSpansParts = spansParts;
      };
      flow.collapseTo(const DocumentTextPosition('a', 2));
      flow.extendTo(const DocumentTextPosition('c', 3));

      flow.deleteSelection();

      expect(pruned, {'b'});
      expect(sawSpansParts, isTrue);
    });

    test('a partial delete prunes nothing', () {
      final flow = _flowWith({'a': 'alpha', 'b': 'beta'});
      var called = false;
      flow.onPruneStructures = (ids, {required spansParts}) => called = true;
      flow.collapseTo(const DocumentTextPosition('a', 2));
      flow.extendTo(const DocumentTextPosition('b', 2));

      flow.deleteSelection();

      expect(called, isFalse);
    });
  });

  group('vertical movement treats a part as a line', () {
    test('moving up lands on the last line of a multi-line paragraph', () {
      final flow = _flowWith({
        paragraphSegmentId('b1'): 'first line\nsecond line',
        listItemSegmentId('b2', 0): 'bullet',
      });

      final target = flow.positionAbove(
        const DocumentTextPosition('b2#i0', 3),
        preferredOffset: 3,
      );

      // "second line" starts at 11, so column 3 of the last line is offset 14 —
      // not offset 3, which would be the first line.
      expect(target, const DocumentTextPosition('b1', 14));
    });

    test('moving down lands on the first line of the target', () {
      final flow = _flowWith({
        listItemSegmentId('b1', 0): 'bullet',
        paragraphSegmentId('b2'): 'first line\nsecond line',
      });

      final target = flow.positionBelow(
        const DocumentTextPosition('b1#i0', 3),
        preferredOffset: 3,
      );

      expect(target, const DocumentTextPosition('b2', 3));
    });

    test('moving down clamps to the end of a short first line', () {
      final flow = _flowWith({
        listItemSegmentId('b1', 0): 'a long bullet',
        paragraphSegmentId('b2'): 'hi\nlonger second line',
      });

      final target = flow.positionBelow(
        const DocumentTextPosition('b1#i0', 9),
        preferredOffset: 9,
      );

      expect(target, const DocumentTextPosition('b2', 2));
    });
  });

  group('selection across parts', () {
    test('is reported as spanning only when it leaves one segment', () {
      final flow = _flowWith({'a': 'one', 'b': 'two'});

      flow.collapseTo(const DocumentTextPosition('a', 0));
      expect(flow.spansSegments, isFalse);

      flow.extendTo(const DocumentTextPosition('a', 2));
      expect(flow.spansSegments, isFalse);

      flow.extendTo(const DocumentTextPosition('b', 1));
      expect(flow.spansSegments, isTrue);
    });

    test('covers the tail, whole middles, and the head of the range', () {
      final flow = _flowWith({'a': 'alpha', 'b': 'beta', 'c': 'gamma'});

      flow.collapseTo(const DocumentTextPosition('a', 2));
      flow.extendTo(const DocumentTextPosition('c', 3));

      expect(flow.selectionWithin('a'), const TextSelection(baseOffset: 2, extentOffset: 5));
      expect(flow.selectionWithin('b'), const TextSelection(baseOffset: 0, extentOffset: 4));
      expect(flow.selectionWithin('c'), const TextSelection(baseOffset: 0, extentOffset: 3));
    });

    test('normalizes a backwards selection', () {
      final flow = _flowWith({'a': 'alpha', 'b': 'beta'});

      flow.collapseTo(const DocumentTextPosition('b', 3));
      flow.extendTo(const DocumentTextPosition('a', 1));

      final (start, end) = flow.orderedSelection()!;
      expect(start, const DocumentTextPosition('a', 1));
      expect(end, const DocumentTextPosition('b', 3));
      expect(flow.selectedText(), 'lpha\nbet');
    });

    test('leaves segments outside the range unhighlighted', () {
      final flow = _flowWith({'a': 'alpha', 'b': 'beta', 'c': 'gamma'});

      flow.collapseTo(const DocumentTextPosition('a', 0));
      flow.extendTo(const DocumentTextPosition('a', 3));

      expect(flow.selectionWithin('b'), isNull);
      expect(flow.selectionWithin('c'), isNull);
      expect(flow.segmentsInSelection(), ['a']);
    });

    test('joins text across parts with newlines', () {
      final flow = _flowWith({
        paragraphSegmentId('b1'): 'intro text',
        listItemSegmentId('b2', 0): 'bullet one',
        tableCellSegmentId('b3', 0, 0): 'cell text',
      });

      flow.collapseTo(const DocumentTextPosition('b1', 6));
      flow.extendTo(const DocumentTextPosition('b3#c0:0', 4));

      expect(flow.selectedText(), 'text\nbullet one\ncell');
      expect(flow.segmentsInSelection(), ['b1', 'b2#i0', 'b3#c0:0']);
    });

    test('drops a selection whose segments disappear from the document', () {
      final flow = _flowWith({'a': 'alpha', 'b': 'beta'});
      flow.collapseTo(const DocumentTextPosition('a', 0));
      flow.extendTo(const DocumentTextPosition('b', 2));

      flow.setOrder(['a']);

      expect(flow.selection, isNull);
    });
  });

  group('pointer miss in empty space', () {
    test('click below text lands at the end of the last line above', () {
      final at = DocumentTextFlow.resolvePointerMiss(
        order: ['a', 'b'],
        tops: {'a': 0, 'b': 40},
        bottoms: {'a': 30, 'b': 70},
        dy: 120,
        lengthOf: (id) => id == 'a' ? 5 : 8,
      );

      expect(at, const DocumentTextPosition('b', 8));
    });

    test('click in the gap between parts lands at the end of the part above', () {
      final at = DocumentTextFlow.resolvePointerMiss(
        order: ['a', 'b'],
        tops: {'a': 0, 'b': 50},
        bottoms: {'a': 30, 'b': 80},
        dy: 40,
        lengthOf: (id) => id == 'a' ? 5 : 8,
      );

      expect(at, const DocumentTextPosition('a', 5));
    });

    test('click above the file lands at the start of the first line', () {
      final at = DocumentTextFlow.resolvePointerMiss(
        order: ['a', 'b'],
        tops: {'a': 20, 'b': 60},
        bottoms: {'a': 50, 'b': 90},
        dy: 5,
        lengthOf: (_) => 4,
      );

      expect(at, const DocumentTextPosition('a', 0));
    });

    test('empty file still resolves to the only segment end', () {
      final at = DocumentTextFlow.resolvePointerMiss(
        order: ['only'],
        tops: {'only': 0},
        bottoms: {'only': 24},
        dy: 200,
        lengthOf: (_) => 0,
      );

      expect(at, const DocumentTextPosition('only', 0));
    });
  });

}
