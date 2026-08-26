import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/model/document_model.dart';
import 'package:system_app_front_end/areas/files/rich_text/rich_table_editor.dart';
import 'package:system_app_front_end/areas/files/rich_text/rtl/rtl.dart';
import 'package:system_app_front_end/core/l10n/app_strings.dart';

TableNode _grid(List<List<String>> cells) {
  return TableNode(
    id: 't1',
    rows: [
      for (final row in cells)
        [for (final text in row) DocumentTableCell(text: text)],
    ],
  );
}

Future<GlobalKey<RichTableEditorState>> _pumpTable(
  WidgetTester tester,
  TableNode node, {
  TextDirection direction = TextDirection.ltr,
  required void Function(TableNode) onChanged,
}) async {
  final key = GlobalKey<RichTableEditorState>();
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: RichTableEditor(
            key: key,
            node: node,
            strings: AppStrings.en,
            onChanged: onChanged,
          ),
        ),
      ),
    ),
  );
  return key;
}

void main() {
  testWidgets('physical left in a Hebrew UI moves to a higher column', (
    tester,
  ) async {
    var node = _grid([
      ['a', 'b', 'c'],
    ]);
    final key = await _pumpTable(
      tester,
      node,
      direction: TextDirection.rtl,
      onChanged: (n) => node = n,
    );

    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byType(TextField).first)
          .focusNode!
          .hasFocus,
      isTrue,
    );

    key.currentState!.nudge(AxisDirection.left);
    await tester.pump();

    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields[1].focusNode!.hasFocus, isTrue);
    expect(node.rows, hasLength(1));
    expect(node.rows.first, hasLength(3));
  });

  testWidgets('RTL dest: physical left lands at logical start', (tester) async {
    var node = _grid([
      ['שלום', 'עולם'],
    ]);
    final key = await _pumpTable(
      tester,
      node,
      direction: TextDirection.rtl,
      onChanged: (n) => node = n,
    );

    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    key.currentState!.nudge(AxisDirection.left);
    await tester.pump();

    final dest = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList()[1];
    expect(dest.focusNode!.hasFocus, isTrue);
    expect(dest.controller!.selection.baseOffset, 0);
  });

  testWidgets('LTR dest: physical left lands at logical end', (tester) async {
    var node = _grid([
      ['hello', 'world'],
    ]);
    final key = await _pumpTable(tester, node, onChanged: (n) => node = n);

    await tester.tap(find.byType(TextField).at(1));
    await tester.pump();
    key.currentState!.nudge(AxisDirection.left);
    await tester.pump();

    final dest = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList()[0];
    expect(dest.focusNode!.hasFocus, isTrue);
    expect(dest.controller!.selection.baseOffset, 'hello'.length);
  });

  testWidgets('empty cell Backspace moves to the previous cell', (
    tester,
  ) async {
    var node = _grid([
      ['hello', ''],
    ]);
    await _pumpTable(tester, node, onChanged: (n) => node = n);

    await tester.tap(find.byType(TextField).at(1));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields[0].focusNode!.hasFocus, isTrue);
    expect(fields[0].controller!.selection.baseOffset, 'hello'.length);
    expect(node.rows, hasLength(1));
    expect(node.rows.first, hasLength(2));
  });

  testWidgets('empty first cell of an empty row deletes the row', (
    tester,
  ) async {
    var node = _grid([
      ['keep', 'this'],
      ['', ''],
    ]);
    await _pumpTable(tester, node, onChanged: (n) => node = n);

    await tester.tap(find.byType(TextField).at(2));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    await tester.pump();

    expect(node.rows, hasLength(1));
    expect(node.rows[0][0].text, 'keep');
    expect(node.rows[0][1].text, 'this');
  });

  testWidgets('clearing one cell keeps focus and does not delete the row', (
    tester,
  ) async {
    var node = _grid([
      ['hello', 'world'],
    ]);
    final key = GlobalKey<RichTableEditorState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return RichTableEditor(
                key: key,
                node: node,
                strings: AppStrings.en,
                onChanged: (n) => setState(() => node = n),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump();

    expect(key.currentState!.hasInnerFocus, isTrue);
    expect(node.rows, hasLength(1));
    expect(node.rows.first, hasLength(2));
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('wrapVisualCaretMotion keeps the Actions parent across LTR↔RTL', (
    tester,
  ) async {
    final childKey = GlobalKey();
    final actions = rtlCaretMotionActions(shouldFlip: () => false);

    await tester.pumpWidget(
      MaterialApp(
        home: wrapVisualCaretMotion(
          textDirection: TextDirection.ltr,
          actions: actions,
          child: SizedBox(key: childKey, width: 1, height: 1),
        ),
      ),
    );
    final element = childKey.currentContext!;
    expect(element.findAncestorWidgetOfExactType<Actions>(), isNotNull);

    await tester.pumpWidget(
      MaterialApp(
        home: wrapVisualCaretMotion(
          textDirection: TextDirection.rtl,
          actions: actions,
          child: SizedBox(key: childKey, width: 1, height: 1),
        ),
      ),
    );
    expect(identical(element, childKey.currentContext), isTrue);
    expect(
      childKey.currentContext!.findAncestorWidgetOfExactType<Actions>(),
      isNotNull,
    );
  });
}
