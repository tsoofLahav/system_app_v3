import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/features/blocks/block_text_focus.dart';
import 'package:system_app_front_end/features/blocks/format_range.dart';
import 'package:system_app_front_end/features/blocks/rich_text_block_sync.dart';
import 'package:system_app_front_end/features/blocks/span_text_editing_controller.dart';
import 'package:system_app_front_end/features/blocks/text_formatting.dart';

void main() {
  test('insert after bold run does not extend bold', () {
    var spans = <Map<String, dynamic>>[
      {'start': 0, 'end': 5, 'bold': true},
    ];
    spans = shiftSpansForEdit(
      spans,
      start: 5,
      removedLength: 0,
      insertedLength: 1,
      textLength: 12,
    );
    expect(spans, [
      {'start': 0, 'end': 5, 'bold': true},
    ]);
  });

  test('controller keeps bold bounded when typing after bold word', () {
    final c = SpanTextEditingController(
      text: 'hello world',
      spans: [
        {'start': 0, 'end': 5, 'bold': true},
      ],
    );
    c.value = c.value.copyWith(
      text: 'hellox world',
      selection: const TextSelection.collapsed(offset: 6),
    );
    expect(c.spans, [
      {'start': 0, 'end': 5, 'bold': true},
    ]);

    c.value = c.value.copyWith(
      text: 'hello worldx',
      selection: const TextSelection.collapsed(offset: 12),
    );
    expect(c.spans, [
      {'start': 0, 'end': 5, 'bold': true},
    ]);
  });

  test('apply bold then type after selection end', () {
    final c = SpanTextEditingController(text: 'hello world');
    c.applyFormatAction(
      'text:bold',
      range: const FormatRange(start: 0, end: 5),
      baseFontSize: 12.5,
    );
    expect(c.spans, [
      {'start': 0, 'end': 5, 'bold': true},
    ]);

    c.value = c.value.copyWith(
      text: 'hello! world',
      selection: const TextSelection.collapsed(offset: 6),
    );
    expect(c.spans, [
      {'start': 0, 'end': 5, 'bold': true},
    ]);
  });

  test('format range uses selection when marked', () {
    final range = FormatRange.resolve(
      'hello world',
      const TextSelection(baseOffset: 0, extentOffset: 5),
    );
    expect(range, const FormatRange(start: 0, end: 5));
  });

  test('format range uses paragraph when caret only', () {
    final range = FormatRange.resolve(
      'line one\nline two',
      const TextSelection.collapsed(offset: 9),
    );
    expect(range, const FormatRange(start: 9, end: 17));
  });

  test('pending selection is not overwritten after focus loss', () {
    FormatRange.clearPending();
    FormatRange.capturePending(
      'hello world',
      const TextSelection(baseOffset: 0, extentOffset: 5),
    );
    FormatRange.capturePending(
      'hello world',
      const TextSelection.collapsed(offset: 5),
    );
    final range = FormatRange.consume(
      'hello world',
      const TextSelection.collapsed(offset: 5),
    );
    expect(range, const FormatRange(start: 0, end: 5));
  });

  test('wrongly bolded paragraph extends on inline insert', () {
    // Whole-line bold (selection lost before menu) — why capturePending matters.
    final c = SpanTextEditingController(
      text: 'hello world',
      spans: [
        {'start': 0, 'end': 11, 'bold': true},
      ],
    );
    c.value = c.value.copyWith(
      text: 'hello! world',
      selection: const TextSelection.collapsed(offset: 6),
    );
    expect(c.spans, [
      {'start': 0, 'end': 12, 'bold': true},
    ]);
  });

  test('remap extends bold only when typing inside a span', () {
    final c = SpanTextEditingController(
      text: 'hello',
      spans: [
        {'start': 0, 'end': 5, 'bold': true},
      ],
    );
    c.value = c.value.copyWith(
      text: 'helxlo',
      selection: const TextSelection.collapsed(offset: 4),
    );
    expect(c.spans, [
      {'start': 0, 'end': 6, 'bold': true},
    ]);
  });

  test('size_up on mixed bold and regular preserves style separation', () {
    const baseFontSize = 12.5;
    final spans = applyFormatActionToRange(
      [
        {'start': 0, 'end': 4, 'bold': true},
      ],
      start: 0,
      end: 9,
      textLength: 9,
      action: 'text:size_up',
      baseFontSize: baseFontSize,
    );
    expect(spans, [
      {'start': 0, 'end': 4, 'bold': true, 'size': 13.5},
      {'start': 4, 'end': 9, 'size': 13.5},
    ]);
  });

  test('size_up on regular-only sub-range leaves bold portion unchanged', () {
    const baseFontSize = 12.5;
    final spans = applyFormatActionToRange(
      [
        {'start': 0, 'end': 4, 'bold': true},
      ],
      start: 4,
      end: 9,
      textLength: 9,
      action: 'text:size_up',
      baseFontSize: baseFontSize,
    );
    expect(spans, [
      {'start': 0, 'end': 4, 'bold': true},
      {'start': 4, 'end': 9, 'size': 13.5},
    ]);
  });

  test('frozen selection boxes respect rtl start alignment', () {
    const hebrew = 'שלום';
    final painter = TextPainter(
      text: TextSpan(text: hebrew, style: const TextStyle(fontSize: 14)),
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.start,
      textWidthBasis: TextWidthBasis.parent,
    )..layout(minWidth: 300, maxWidth: 300);

    final boxes = painter.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: hebrew.length),
    );
    expect(boxes.first.left, greaterThan(200));
    expect(boxes.last.right, 300);
  });

  test('idle sync skips active registry controller', () {
    final focusNode = FocusNode();
    final controller = SpanTextEditingController(
      text: 'hello world',
      spans: [
        {'start': 0, 'end': 5, 'bold': true},
      ],
    );

    BlockTextFocusRegistry.register(
      controller: controller,
      changed: () {},
      focusNode: focusNode,
    );

    syncRichControllerFromBlockIfIdle(
      focusNode: focusNode,
      blockContent: {
        'text': 'hello world',
        'spans': [
          {'start': 0, 'end': 11, 'bold': true},
        ],
      },
      controller: controller,
    );

    expect(controller.spans, [
      {'start': 0, 'end': 5, 'bold': true},
    ]);

    BlockTextFocusRegistry.unregister(controller);
    focusNode.dispose();
    controller.dispose();
  });
}
