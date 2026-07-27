import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/editor/document_mark.dart';
import 'package:system_app_front_end/areas/files/editor/document_text_flow.dart';
import 'package:system_app_front_end/areas/files/rich_text/span_text_editing_controller.dart';

class _Segment {
  _Segment(this.controller, this.node);

  final SpanTextEditingController controller;
  final FocusNode node;
  int changeCount = 0;
}

/// A flow with attached segments, mirroring paragraph / bullet / cell fields.
({DocumentTextFlow flow, Map<String, _Segment> segments}) _build(
  Map<String, String> texts,
) {
  final flow = DocumentTextFlow()..setOrder(texts.keys.toList());
  final segments = <String, _Segment>{};
  texts.forEach((id, text) {
    final segment = _Segment(
      SpanTextEditingController(text: text),
      FocusNode(),
    );
    segments[id] = segment;
    flow.register(
      id,
      segment.controller,
      segment.node,
      onChanged: () => segment.changeCount++,
    );
  });
  return (flow: flow, segments: segments);
}

void main() {
  // applyFormat defers its change notification to after the current frame.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('one marking rule', () {
    test('uses the selection when something is marked', () {
      final built = _build({'a': 'alpha text', 'b': 'beta text'});
      built.flow.collapseTo(const DocumentTextPosition('a', 6));
      built.flow.extendTo(const DocumentTextPosition('b', 4));

      final mark = DocumentMark.resolve(built.flow);

      expect(mark.isValid, isTrue);
      expect(mark.spansParts, isTrue);
      expect(mark.text, 'text\nbeta');
    });

    test('falls back to the caret line when nothing is marked', () {
      final built = _build({'a': 'first line\nsecond line', 'b': 'other'});
      // Caret inside "second line", nothing marked.
      built.flow.collapseTo(const DocumentTextPosition('a', 14));

      final mark = DocumentMark.resolve(built.flow);

      expect(mark.isValid, isTrue);
      expect(mark.spansParts, isFalse);
      expect(mark.text, 'second line');
    });

    test('the caret-line fallback stays inside the caret part', () {
      final built = _build({'a': 'alpha', 'b': 'beta'});
      built.flow.collapseTo(const DocumentTextPosition('b', 2));

      final mark = DocumentMark.resolve(built.flow);

      expect(mark.spans.single.segmentId, 'b');
      expect(mark.text, 'beta');
    });

    test('a marked range inside one part does not become the whole line', () {
      final built = _build({'a': 'alpha beta', 'b': 'other'});
      built.flow.collapseTo(const DocumentTextPosition('a', 0));
      built.flow.extendTo(const DocumentTextPosition('a', 5));

      final mark = DocumentMark.resolve(built.flow);

      expect(mark.text, 'alpha');
      expect(mark.spansParts, isFalse);
    });
  });

  group('actions run on the whole mark', () {
    test('delete clears every part and keeps them all', () {
      final built = _build({'a': 'alpha', 'b': 'beta', 'c': 'gamma'});
      built.flow.collapseTo(const DocumentTextPosition('a', 2));
      built.flow.extendTo(const DocumentTextPosition('c', 3));

      final changed = DocumentMark.resolve(built.flow).delete();

      expect(changed, isTrue);
      expect(built.segments['a']!.controller.text, 'al');
      expect(built.segments['b']!.controller.text, '');
      expect(built.segments['c']!.controller.text, 'ma');
      // Every touched part reported its change to the document model.
      expect(built.segments['a']!.changeCount, 1);
      expect(built.segments['b']!.changeCount, 1);
      expect(built.segments['c']!.changeCount, 1);
    });

    test('replace puts the new text in the first part', () {
      final built = _build({'a': 'alpha', 'b': 'beta'});
      built.flow.collapseTo(const DocumentTextPosition('a', 2));
      built.flow.extendTo(const DocumentTextPosition('b', 2));

      DocumentMark.resolve(built.flow).replaceWith('X');

      expect(built.segments['a']!.controller.text, 'alX');
      expect(built.segments['b']!.controller.text, 'ta');
    });

    test('formatting reaches every marked part', () {
      final built = _build({'a': 'alpha', 'b': 'beta'});
      built.flow.collapseTo(const DocumentTextPosition('a', 0));
      built.flow.extendTo(const DocumentTextPosition('b', 4));

      final applied = DocumentMark.resolve(built.flow)
          .applyFormat('text:bold', baseFontSize: 12.5);

      expect(applied, isTrue);
      expect(built.segments['a']!.controller.spans, isNotEmpty);
      expect(built.segments['b']!.controller.spans, isNotEmpty);
    });

    test('formatting with nothing marked applies to the caret line only', () {
      final built = _build({'a': 'alpha', 'b': 'beta'});
      built.flow.collapseTo(const DocumentTextPosition('a', 2));

      DocumentMark.resolve(built.flow)
          .applyFormat('text:bold', baseFontSize: 12.5);

      expect(built.segments['a']!.controller.spans, isNotEmpty);
      expect(built.segments['b']!.controller.spans, isEmpty);
    });

    test('a lone field with no flow still resolves a mark', () {
      final controller = SpanTextEditingController(text: 'one\ntwo');
      controller.selection = const TextSelection.collapsed(offset: 5);

      final mark = DocumentMark.resolveForController(controller);

      expect(mark.text, 'two');
      expect(mark.spansParts, isFalse);
    });
  });
}
