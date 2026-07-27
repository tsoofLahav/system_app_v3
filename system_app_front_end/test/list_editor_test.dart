import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/model/document_model.dart';
import 'package:system_app_front_end/areas/files/rich_text/list_editor.dart';
import 'package:system_app_front_end/core/l10n/app_strings.dart';

/// The parent applies list edits without rebuilding, so `node` stays at the
/// value from the last build while the editor's own state moves ahead.
/// These tests pin the editor's behaviour under that condition.
Future<List<ListNode>> _pumpEditor(
  WidgetTester tester,
  ListNode node, {
  required List<int> exitCalls,
}) async {
  final emitted = <ListNode>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RichListEditor(
          node: node,
          strings: AppStrings.en,
          onChanged: emitted.add,
          onExitList: exitCalls.add,
        ),
      ),
    ),
  );
  return emitted;
}

void main() {
  testWidgets('inserting an item keeps existing item ids and indents stable',
      (tester) async {
    final node = ListNode(
      id: 'b1',
      items: const [
        ListItem(id: 'li-a', text: 'A', indent: 1),
        ListItem(id: 'li-b', text: 'B', indent: 2),
      ],
    );
    final exitCalls = <int>[];
    final emitted = await _pumpEditor(tester, node, exitCalls: exitCalls);

    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(exitCalls, isEmpty);
    expect(emitted, isNotEmpty);

    final result = emitted.last;
    expect(result.items.map((i) => i.text).toList(), ['A', '', 'B']);
    // Regression: ids were assigned positionally against the stale node, so
    // the new item stole 'li-b' and 'B' received a freshly generated id.
    expect(result.items[0].id, 'li-a');
    expect(result.items[2].id, 'li-b');
    expect(result.items[1].id, isNot(anyOf('li-a', 'li-b')));
    expect(result.items.map((i) => i.indent).toList(), [1, 1, 2]);
  });

  testWidgets('enter on an inserted empty item exits with that item index',
      (tester) async {
    final node = ListNode(
      id: 'b1',
      items: const [
        ListItem(id: 'li-a', text: 'A'),
        ListItem(id: 'li-b', text: 'B'),
      ],
    );
    final exitCalls = <int>[];
    await _pumpEditor(tester, node, exitCalls: exitCalls);

    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    // The new empty item sits at index 1; exiting must report that index so
    // the parent drops the empty item rather than a sibling that has text.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(exitCalls, [1]);
  });

  testWidgets('edits made without a parent rebuild survive in the emitted node',
      (tester) async {
    final node = ListNode(
      id: 'b1',
      items: const [ListItem(id: 'li-a', text: 'A')],
    );
    final exitCalls = <int>[];
    final emitted = await _pumpEditor(tester, node, exitCalls: exitCalls);

    await tester.enterText(find.byType(TextField).first, 'A edited');
    await tester.pumpAndSettle();

    expect(emitted.last.items.single.text, 'A edited');
    expect(emitted.last.items.single.id, 'li-a');
  });
}
