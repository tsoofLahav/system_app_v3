import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/editor/document_secondary_tap.dart';
import 'package:system_app_front_end/areas/files/editor/document_text_flow.dart';
import 'package:system_app_front_end/areas/files/rich_text/block_text_actions.dart';
import 'package:system_app_front_end/areas/files/rich_text/block_text_focus.dart';
import 'package:system_app_front_end/areas/files/rich_text/formatted_text_field.dart';
import 'package:system_app_front_end/areas/files/rich_text/span_text_editing_controller.dart';

/// Mirrors how the editor hosts a paragraph, list bullets and table cells:
/// separate text fields sharing one document text flow.
class _Harness extends StatefulWidget {
  const _Harness({
    required this.flow,
    required this.segments,
    this.textDirection = TextDirection.ltr,
  });

  final DocumentTextFlow flow;
  final Map<String, String> segments;
  final TextDirection textDirection;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late final Map<String, SpanTextEditingController> controllers = {
    for (final entry in widget.segments.entries)
      entry.key: SpanTextEditingController(text: entry.value),
  };

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.flow.setOrder(widget.segments.keys.toList());
    return MaterialApp(
      home: Directionality(
        textDirection: widget.textDirection,
        child: Scaffold(
          body: DocumentTextFlowScope(
            flow: widget.flow,
            child: Column(
              children: [
                for (final id in widget.segments.keys)
                  FormattedTextField(
                    key: ValueKey(id),
                    controller: controllers[id]!,
                    segmentId: id,
                    style: const TextStyle(fontSize: 14),
                    maxLines: null,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<_HarnessState> _pump(
  WidgetTester tester,
  DocumentTextFlow flow,
  Map<String, String> segments, {
  TextDirection textDirection = TextDirection.ltr,
}) async {
  await tester.pumpWidget(
    _Harness(flow: flow, segments: segments, textDirection: textDirection),
  );
  await tester.pumpAndSettle();
  return tester.state<_HarnessState>(find.byType(_Harness));
}

Future<void> _placeCaret(
  WidgetTester tester,
  _HarnessState state,
  String segmentId,
  int offset,
) async {
  await tester.tap(find.byKey(ValueKey(segmentId)));
  await tester.pumpAndSettle();
  state.controllers[segmentId]!.selection = TextSelection.collapsed(
    offset: offset,
  );
  await tester.pumpAndSettle();
}

void _linkLtrTable(DocumentTextFlow flow, String id, int rows, int cols) {
  final above = <String, String>{};
  final below = <String, String>{};
  final left = <String, String>{};
  final right = <String, String>{};
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      final cell = tableCellSegmentId(id, r, c);
      if (r > 0) above[cell] = tableCellSegmentId(id, r - 1, c);
      if (r + 1 < rows) below[cell] = tableCellSegmentId(id, r + 1, c);
      if (c > 0) left[cell] = tableCellSegmentId(id, r, c - 1);
      if (c + 1 < cols) right[cell] = tableCellSegmentId(id, r, c + 1);
    }
  }
  flow.setVerticalLinks(above: above, below: below);
  flow.setHorizontalLinks(left: left, right: right);
}

void main() {
  testWidgets('right arrow at the end of a paragraph enters the next bullet', (
    tester,
  ) async {
    final flow = DocumentTextFlow();
    final segments = {
      paragraphSegmentId('b1'): 'intro',
      listItemSegmentId('b2', 0): 'bullet',
    };
    final state = await _pump(tester, flow, segments);
    await _placeCaret(tester, state, 'b1', 5);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(flow.selection?.focus, const DocumentTextPosition('b2#i0', 0));
    expect(flow.focusNodeFor('b2#i0')!.hasFocus, isTrue);
  });

  testWidgets(
    'left arrow at the start of a bullet returns to the paragraph end',
    (tester) async {
      final flow = DocumentTextFlow();
      final segments = {
        paragraphSegmentId('b1'): 'intro',
        listItemSegmentId('b2', 0): 'bullet',
      };
      final state = await _pump(tester, flow, segments);
      await _placeCaret(tester, state, 'b2#i0', 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();

      expect(flow.selection?.focus, const DocumentTextPosition('b1', 5));
      expect(flow.focusNodeFor('b1')!.hasFocus, isTrue);
    },
  );

  group('in Hebrew the arrows still point where they point', () {
    // The caret follows the arrow on screen, so in right-to-left text the left
    // arrow walks forward through the string and the right arrow back. Within a
    // part the text field still does the moving; `rtlCaretMotionActions` only
    // flips the motion intents it dispatches.
    const hebrew = {'b1': 'שלום', 'b2': 'עולם'};

    testWidgets('left arrow moves forward through the text', (tester) async {
      final flow = DocumentTextFlow();
      final state = await _pump(
        tester,
        flow,
        hebrew,
        textDirection: TextDirection.rtl,
      );
      await _placeCaret(tester, state, 'b1', 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();

      expect(state.controllers['b1']!.selection.baseOffset, 2);
    });

    testWidgets('right arrow moves back through the text', (tester) async {
      final flow = DocumentTextFlow();
      final state = await _pump(
        tester,
        flow,
        hebrew,
        textDirection: TextDirection.rtl,
      );
      await _placeCaret(tester, state, 'b1', 2);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(state.controllers['b1']!.selection.baseOffset, 1);
    });

    testWidgets('in English the same keys are left alone', (tester) async {
      final flow = DocumentTextFlow();
      final state = await _pump(tester, flow, {'b1': 'hello', 'b2': 'world'});
      await _placeCaret(tester, state, 'b1', 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();

      expect(state.controllers['b1']!.selection.baseOffset, 0);
    });

    testWidgets('left arrow at the visual edge crosses into the next part', (
      tester,
    ) async {
      final flow = DocumentTextFlow();
      final state = await _pump(
        tester,
        flow,
        hebrew,
        textDirection: TextDirection.rtl,
      );
      await _placeCaret(tester, state, 'b1', 4);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();

      expect(flow.selection?.focus, const DocumentTextPosition('b2', 0));
      expect(flow.focusNodeFor('b2')!.hasFocus, isTrue);
    });

    testWidgets('a held arrow keeps going the same way', (tester) async {
      final flow = DocumentTextFlow();
      final state = await _pump(
        tester,
        flow,
        hebrew,
        textDirection: TextDirection.rtl,
      );
      await _placeCaret(tester, state, 'b1', 0);

      // Key repeats must move the caret the same direction as the first press.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();

      expect(state.controllers['b1']!.selection.baseOffset, 3);
    });

    testWidgets('right arrow at the visual edge returns to the previous part', (
      tester,
    ) async {
      final flow = DocumentTextFlow();
      final state = await _pump(
        tester,
        flow,
        hebrew,
        textDirection: TextDirection.rtl,
      );
      await _placeCaret(tester, state, 'b2', 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(flow.selection?.focus, const DocumentTextPosition('b1', 4));
      expect(flow.focusNodeFor('b1')!.hasFocus, isTrue);
    });
  });

  testWidgets('arrow keys inside a part do not leave it', (tester) async {
    final flow = DocumentTextFlow();
    final segments = {
      paragraphSegmentId('b1'): 'intro',
      listItemSegmentId('b2', 0): 'bullet',
    };
    final state = await _pump(tester, flow, segments);
    await _placeCaret(tester, state, 'b1', 2);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(flow.focusNodeFor('b1')!.hasFocus, isTrue);
    expect(flow.focusNodeFor('b2#i0')!.hasFocus, isFalse);
  });

  testWidgets('shift+arrow builds a selection that spans two parts', (
    tester,
  ) async {
    final flow = DocumentTextFlow();
    final segments = {
      paragraphSegmentId('b1'): 'intro',
      listItemSegmentId('b2', 0): 'bullet',
    };
    final state = await _pump(tester, flow, segments);
    await _placeCaret(tester, state, 'b1', 3);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    // First press crosses the boundary and selects just the break between parts.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(flow.spansSegments, isTrue);
    expect(flow.segmentsInSelection(), ['b1', 'b2#i0']);
    expect(flow.selectedText(), '\n');

    // Further presses eat into the next part.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);

    expect(flow.selectedText(), '\nb');
    expect(
      flow.selectionWithin('b2#i0'),
      const TextSelection(baseOffset: 0, extentOffset: 1),
    );
  });

  testWidgets('shift+down marks across two task rows', (tester) async {
    final flow = DocumentTextFlow();
    final segments = {
      taskItemSegmentId('list', 0): 'one',
      taskItemSegmentId('list', 1): 'two',
    };
    final state = await _pump(tester, flow, segments);
    await _placeCaret(tester, state, taskItemSegmentId('list', 0), 0);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);

    expect(flow.spansSegments, isTrue);
    expect(flow.segmentsInSelection(), [
      taskItemSegmentId('list', 0),
      taskItemSegmentId('list', 1),
    ]);
  });

  testWidgets('down arrow in a table cell moves by column, not reading order', (
    tester,
  ) async {
    final flow = DocumentTextFlow();
    final segments = {
      tableCellSegmentId('t1', 0, 0): 'r0c0',
      tableCellSegmentId('t1', 0, 1): 'r0c1',
      tableCellSegmentId('t1', 1, 0): 'r1c0',
      tableCellSegmentId('t1', 1, 1): 'r1c1',
    };
    final state = await _pump(tester, flow, segments);
    _linkLtrTable(flow, 't1', 2, 2);
    await _placeCaret(tester, state, tableCellSegmentId('t1', 0, 1), 2);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    // Reading order would have gone to r1c0; column order gives r1c1.
    expect(flow.selection?.focus.segmentId, tableCellSegmentId('t1', 1, 1));
  });

  testWidgets('shift+down marks the column, including the first cell', (
    tester,
  ) async {
    final flow = DocumentTextFlow();
    final segments = {
      tableCellSegmentId('t1', 0, 0): 'r0c0',
      tableCellSegmentId('t1', 0, 1): 'r0c1',
      tableCellSegmentId('t1', 1, 0): 'r1c0',
      tableCellSegmentId('t1', 1, 1): 'r1c1',
    };
    final state = await _pump(tester, flow, segments);
    _linkLtrTable(flow, 't1', 2, 2);
    await _placeCaret(tester, state, tableCellSegmentId('t1', 0, 0), 4);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);

    expect(flow.segmentsInSelection(), [
      tableCellSegmentId('t1', 0, 0),
      tableCellSegmentId('t1', 1, 0),
    ]);
    expect(
      flow.selectionWithin(tableCellSegmentId('t1', 0, 0)),
      const TextSelection(baseOffset: 0, extentOffset: 4),
    );
    expect(flow.selectionWithin(tableCellSegmentId('t1', 0, 1)), isNull);
  });

  testWidgets('shift+right widens a table mark to the side', (tester) async {
    final flow = DocumentTextFlow();
    final segments = {
      tableCellSegmentId('t1', 0, 0): 'r0c0',
      tableCellSegmentId('t1', 0, 1): 'r0c1',
      tableCellSegmentId('t1', 1, 0): 'r1c0',
      tableCellSegmentId('t1', 1, 1): 'r1c1',
    };
    final state = await _pump(tester, flow, segments);
    _linkLtrTable(flow, 't1', 2, 2);
    await _placeCaret(tester, state, tableCellSegmentId('t1', 0, 0), 0);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);

    expect(flow.segmentsInSelection(), [
      tableCellSegmentId('t1', 0, 0),
      tableCellSegmentId('t1', 0, 1),
    ]);
    expect(flow.selectionWithin(tableCellSegmentId('t1', 1, 0)), isNull);
  });

  testWidgets('select all covers every part of the file', (tester) async {
    final flow = DocumentTextFlow();
    final segments = {
      paragraphSegmentId('b1'): 'intro',
      listItemSegmentId('b2', 0): 'bullet',
      tableCellSegmentId('b3', 0, 0): 'cell',
    };
    final state = await _pump(tester, flow, segments);
    await _placeCaret(tester, state, 'b2#i0', 2);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);

    expect(flow.selectedText(), 'intro\nbullet\ncell');
  });

  testWidgets('backspace removes a selection spanning parts', (tester) async {
    final flow = DocumentTextFlow();
    final segments = {
      paragraphSegmentId('b1'): 'intro',
      listItemSegmentId('b2', 0): 'bullet',
      tableCellSegmentId('b3', 0, 0): 'cell',
    };
    final state = await _pump(tester, flow, segments);
    await _placeCaret(tester, state, 'b1', 2);
    flow.extendTo(const DocumentTextPosition('b3#c0:0', 2));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();

    expect(state.controllers['b1']!.text, 'in');
    // The fully covered middle part is emptied but kept.
    expect(state.controllers['b2#i0']!.text, '');
    expect(state.controllers['b3#c0:0']!.text, 'll');
    expect(flow.spansSegments, isFalse);
  });

  testWidgets('typing replaces a selection spanning parts', (tester) async {
    final flow = DocumentTextFlow();
    final segments = {
      paragraphSegmentId('b1'): 'intro',
      listItemSegmentId('b2', 0): 'bullet',
    };
    final state = await _pump(tester, flow, segments);
    await _placeCaret(tester, state, 'b1', 2);
    flow.extendTo(const DocumentTextPosition('b2#i0', 3));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.pumpAndSettle();

    expect(state.controllers['b1']!.text, 'inx');
    expect(state.controllers['b2#i0']!.text, 'let');
  });

  testWidgets('a screen point resolves to the part under it', (tester) async {
    final flow = DocumentTextFlow();
    final segments = {
      paragraphSegmentId('b1'): 'intro',
      listItemSegmentId('b2', 0): 'bullet',
      tableCellSegmentId('b3', 0, 0): 'cell',
    };
    await _pump(tester, flow, segments);

    final bullet = tester.getCenter(find.byKey(const ValueKey('b2#i0')));
    expect(flow.positionAtGlobal(bullet)?.segmentId, 'b2#i0');

    final cell = tester.getCenter(find.byKey(const ValueKey('b3#c0:0')));
    expect(flow.positionAtGlobal(cell)?.segmentId, 'b3#c0:0');
  });

  testWidgets('dragging past the end resolves to the nearest part', (
    tester,
  ) async {
    final flow = DocumentTextFlow();
    final segments = {
      paragraphSegmentId('b1'): 'intro',
      listItemSegmentId('b2', 0): 'bullet',
    };
    await _pump(tester, flow, segments);

    final farBelow =
        tester.getCenter(find.byKey(const ValueKey('b2#i0'))) +
        const Offset(0, 400);

    expect(flow.positionAtGlobal(farBelow)?.segmentId, 'b2#i0');
  });

  group('one marking, one target for actions', () {
    String? clipboard;

    setUp(() {
      clipboard = null;
      BlockTextFocusRegistry.abandonStashedFocus();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboard = (call.arguments as Map)['text'] as String?;
              return null;
            }
            if (call.method == 'Clipboard.getData') {
              return <String, Object?>{'text': clipboard ?? ''};
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
      BlockTextFocusRegistry.abandonStashedFocus();
    });

    testWidgets('a menu action affects every marked part, not just one line', (
      tester,
    ) async {
      final flow = DocumentTextFlow();
      final segments = {
        paragraphSegmentId('b1'): 'alpha',
        listItemSegmentId('b2', 0): 'beta',
        tableCellSegmentId('b3', 0, 0): 'gamma',
      };
      final state = await _pump(tester, flow, segments);
      await _placeCaret(tester, state, 'b1', 2);
      flow.extendTo(const DocumentTextPosition('b3#c0:0', 3));
      await tester.pumpAndSettle();

      // Right-click freezes the target, then the menu runs the action.
      BlockTextFocusRegistry.capturePendingMark();
      BlockTextFocusRegistry.openMenuSession();
      expect(BlockTextFocusRegistry.frozenMark?.spansParts, isTrue);

      await runBlockTextAction('text:cut');
      BlockTextFocusRegistry.closeMenuSession();
      await tester.pumpAndSettle();

      expect(state.controllers['b1']!.text, 'al');
      expect(state.controllers['b2#i0']!.text, '');
      expect(state.controllers['b3#c0:0']!.text, 'ma');
      expect(clipboard, 'pha\nbeta\ngam');
    });

    testWidgets('with nothing marked an action uses the caret line', (
      tester,
    ) async {
      final flow = DocumentTextFlow();
      final segments = {
        paragraphSegmentId('b1'): 'first line\nsecond line',
        listItemSegmentId('b2', 0): 'bullet',
      };
      final state = await _pump(tester, flow, segments);
      await _placeCaret(tester, state, 'b1', 14);

      BlockTextFocusRegistry.capturePendingMark();
      BlockTextFocusRegistry.openMenuSession();

      expect(BlockTextFocusRegistry.markedText(), 'second line');

      await runBlockTextAction('text:cut');
      BlockTextFocusRegistry.closeMenuSession();
      await tester.pumpAndSettle();

      // Only the caret's line went; the other part is untouched.
      expect(state.controllers['b1']!.text, 'first line\n');
      expect(state.controllers['b2#i0']!.text, 'bullet');
      expect(clipboard, 'second line');
    });

    testWidgets('paste without a mark inserts at the caret', (tester) async {
      final flow = DocumentTextFlow();
      final segments = {paragraphSegmentId('b1'): 'hello'};
      final state = await _pump(tester, flow, segments);
      await _placeCaret(tester, state, 'b1', 2);

      clipboard = 'XX';
      await runBlockTextAction('text:paste');
      await tester.pumpAndSettle();

      expect(state.controllers['b1']!.text, 'heXXllo');
    });

    testWidgets('paste over a mark replaces it', (tester) async {
      final flow = DocumentTextFlow();
      final segments = {paragraphSegmentId('b1'): 'hello'};
      final state = await _pump(tester, flow, segments);
      await _placeCaret(tester, state, 'b1', 1);
      flow.collapseTo(const DocumentTextPosition('b1', 1));
      flow.extendTo(const DocumentTextPosition('b1', 4));
      await tester.pumpAndSettle();

      clipboard = 'XX';
      await runBlockTextAction('text:paste');
      await tester.pumpAndSettle();

      expect(state.controllers['b1']!.text, 'hXXo');
    });

    testWidgets('paste with a frozen caret line still inserts', (tester) async {
      final flow = DocumentTextFlow();
      final segments = {paragraphSegmentId('b1'): 'hello'};
      final state = await _pump(tester, flow, segments);
      await _placeCaret(tester, state, 'b1', 2);

      BlockTextFocusRegistry.capturePendingMark();
      BlockTextFocusRegistry.openMenuSession();
      expect(BlockTextFocusRegistry.frozenMark?.fromMarking, isFalse);
      expect(BlockTextFocusRegistry.frozenMark?.text, 'hello');

      clipboard = 'XX';
      await runBlockTextAction('text:paste');
      BlockTextFocusRegistry.closeMenuSession();
      await tester.pumpAndSettle();

      expect(state.controllers['b1']!.text, 'heXXllo');
    });

    testWidgets('right-click aims at the pointer, not the old caret', (
      tester,
    ) async {
      final flow = DocumentTextFlow();
      final segments = {paragraphSegmentId('b1'): 'first line\nsecond line'};
      final state = await _pump(tester, flow, segments);
      await _placeCaret(tester, state, 'b1', 0);
      // A prior mark on this field used to freeze via snapshot, ignoring the
      // pointer — the same leak Super Editor already stopped.
      state.controllers['b1']!.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 10,
      );
      await tester.pump();

      final rect = tester.getRect(
        find.byKey(ValueKey(paragraphSegmentId('b1'))),
      );
      await tester.tapAt(
        Offset(rect.left + 24, rect.bottom - 6),
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();

      BlockTextFocusRegistry.openMenuSession();
      expect(BlockTextFocusRegistry.markedText(), 'second line');
      BlockTextFocusRegistry.closeMenuSession();
      expect(state.controllers['b1']!.text, 'first line\nsecond line');
    });

    testWidgets(
      'a second right-click retargets the mark while a menu is open',
      (tester) async {
        final flow = DocumentTextFlow();
        final segments = {paragraphSegmentId('b1'): 'first line\nsecond line'};
        final state = await _pump(tester, flow, segments);
        await _placeCaret(tester, state, 'b1', 0);

        final rect = tester.getRect(
          find.byKey(ValueKey(paragraphSegmentId('b1'))),
        );
        await tester.tapAt(
          Offset(rect.left + 24, rect.top + 6),
          buttons: kSecondaryMouseButton,
        );
        await tester.pump();
        BlockTextFocusRegistry.openMenuSession();
        expect(BlockTextFocusRegistry.markedText(), 'first line');

        await tester.tapAt(
          Offset(rect.left + 24, rect.bottom - 6),
          buttons: kSecondaryMouseButton,
        );
        await tester.pump();
        BlockTextFocusRegistry.openMenuSession();
        expect(BlockTextFocusRegistry.markedText(), 'second line');
        BlockTextFocusRegistry.closeMenuSession();
      },
    );

    test('a new right-click pointer is not swallowed by the previous menu', () {
      DocumentSecondaryTap.notePointer(1);
      DocumentSecondaryTap.markEmbedHandled();
      expect(DocumentSecondaryTap.embedHandled, isTrue);
      DocumentSecondaryTap.notePointer(2);
      expect(DocumentSecondaryTap.embedHandled, isFalse);
      DocumentSecondaryTap.clearEmbedHandled();
    });

    testWidgets('beginNewPointerAim lets a second menu freeze a new line', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'aaa\nbbb');
      addTearDown(controller.dispose);
      BlockTextFocusRegistry.register(controller: controller, changed: () {});
      addTearDown(() => BlockTextFocusRegistry.unregister(controller));
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 3,
      );
      BlockTextFocusRegistry.capturePendingMark();
      final first = BlockTextFocusRegistry.openMenuSession();
      expect(BlockTextFocusRegistry.markedText(), 'aaa');

      BlockTextFocusRegistry.beginNewPointerAim();
      controller.selection = const TextSelection(
        baseOffset: 4,
        extentOffset: 7,
      );
      BlockTextFocusRegistry.capturePendingMark();
      final second = BlockTextFocusRegistry.openMenuSession();
      expect(BlockTextFocusRegistry.markedText(), 'bbb');

      // Completing the first overlay is async; its finally must not
      // unfreeze the line this right-click just marked.
      BlockTextFocusRegistry.closeMenuSession(first);
      expect(BlockTextFocusRegistry.markedText(), 'bbb');
      BlockTextFocusRegistry.closeMenuSession(second);
    });

    testWidgets('focusing another object field drops the previous mark', (
      tester,
    ) async {
      final flow = DocumentTextFlow();
      final segments = {
        paragraphSegmentId('b1'): 'alpha',
        listItemSegmentId('b2', 0): 'beta',
      };
      final state = await _pump(tester, flow, segments);
      await _placeCaret(tester, state, 'b1', 0);
      state.controllers['b1']!.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      await tester.pump();

      await tester.tap(find.byKey(ValueKey(listItemSegmentId('b2', 0))));
      await tester.pumpAndSettle();

      expect(state.controllers['b1']!.selection.isCollapsed, isTrue);
    });

    testWidgets('copy of a cross-part mark joins the parts', (tester) async {
      final flow = DocumentTextFlow();
      final segments = {
        paragraphSegmentId('b1'): 'alpha',
        listItemSegmentId('b2', 0): 'beta',
      };
      final state = await _pump(tester, flow, segments);
      await _placeCaret(tester, state, 'b1', 0);
      flow.extendTo(const DocumentTextPosition('b2#i0', 4));
      await tester.pumpAndSettle();

      BlockTextFocusRegistry.capturePendingMark();
      BlockTextFocusRegistry.openMenuSession();
      await runBlockTextAction('text:copy');
      BlockTextFocusRegistry.closeMenuSession();
      await tester.pumpAndSettle();

      expect(clipboard, 'alpha\nbeta');
      // Copy leaves the text alone.
      expect(state.controllers['b1']!.text, 'alpha');
      expect(state.controllers['b2#i0']!.text, 'beta');
    });

    testWidgets('formatting applies across every marked part', (tester) async {
      final flow = DocumentTextFlow();
      final segments = {
        paragraphSegmentId('b1'): 'alpha',
        listItemSegmentId('b2', 0): 'beta',
      };
      final state = await _pump(tester, flow, segments);
      await _placeCaret(tester, state, 'b1', 0);
      flow.extendTo(const DocumentTextPosition('b2#i0', 4));
      await tester.pumpAndSettle();

      BlockTextFocusRegistry.capturePendingMark();
      BlockTextFocusRegistry.openMenuSession();
      await runBlockTextAction('text:bold');
      BlockTextFocusRegistry.closeMenuSession();
      await tester.pumpAndSettle();

      expect(state.controllers['b1']!.spans, isNotEmpty);
      expect(state.controllers['b2#i0']!.spans, isNotEmpty);
    });
  });

  testWidgets('caret cannot escape past the last part', (tester) async {
    final flow = DocumentTextFlow();
    final segments = {paragraphSegmentId('b1'): 'only'};
    final state = await _pump(tester, flow, segments);
    await _placeCaret(tester, state, 'b1', 4);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(flow.focusNodeFor('b1')!.hasFocus, isTrue);
  });

  test('releaseLiveMark forgets an object-field mark', () {
    final controller = TextEditingController(text: 'hello world');
    addTearDown(controller.dispose);
    final focus = FocusNode();
    addTearDown(focus.dispose);
    BlockTextFocusRegistry.register(
      controller: controller,
      changed: () {},
      focusNode: focus,
    );
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    BlockTextFocusRegistry.releaseLiveMark();
    expect(controller.selection.isCollapsed, isTrue);
    expect(BlockTextFocusRegistry.activeController, isNull);
  });
}
