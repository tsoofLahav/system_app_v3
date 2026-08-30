import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/rich_text/formatted_text_field.dart';

void main() {
  testWidgets('arrow up after a rebuild does not stack-overflow', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'hello\nworld');
    addTearDown(controller.dispose);

    var tick = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: Column(
                children: [
                  FormattedTextField(
                    controller: controller,
                    style: const TextStyle(fontSize: 14),
                    maxLines: null,
                  ),
                  TextButton(
                    onPressed: () => setState(() => tick++),
                    child: Text('rebuild $tick'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.byType(FormattedTextField));
    await tester.pump();

    await tester.tap(find.textContaining('rebuild'));
    await tester.pump();
    await tester.tap(find.textContaining('rebuild'));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
  });

  testWidgets('focusing an already-visible field does not jump the scroll', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'task title');
    addTearDown(controller.dispose);
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: SingleChildScrollView(
              controller: scrollController,
              child: Column(
                children: [
                  FormattedTextField(
                    controller: controller,
                    style: const TextStyle(fontSize: 14),
                    maxLines: null,
                  ),
                  const SizedBox(height: 1200),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(scrollController.offset, 0);

    await tester.tap(find.byType(FormattedTextField));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(scrollController.offset, 0);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(scrollController.offset, 0);
  });

  test('embed caret correction is only for a collapsed click', () {
    expect(
      shouldApplyEmbedCaretForTap(
        draggedBeyondSlop: false,
        selectionIsRange: false,
        shiftPressed: false,
      ),
      isTrue,
    );
    expect(
      shouldApplyEmbedCaretForTap(
        draggedBeyondSlop: true,
        selectionIsRange: false,
        shiftPressed: false,
      ),
      isFalse,
    );
    expect(
      shouldApplyEmbedCaretForTap(
        draggedBeyondSlop: false,
        selectionIsRange: true,
        shiftPressed: false,
      ),
      isFalse,
    );
    expect(
      shouldApplyEmbedCaretForTap(
        draggedBeyondSlop: false,
        selectionIsRange: false,
        shiftPressed: true,
      ),
      isFalse,
    );
    expect(
      shouldApplyEmbedCaretForTap(
        draggedBeyondSlop: false,
        selectionIsRange: false,
        shiftPressed: false,
        consecutiveTapCount: 2,
      ),
      isFalse,
    );
  });
}
