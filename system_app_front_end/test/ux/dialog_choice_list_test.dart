import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/ui/dialog_field_style.dart';
import 'package:system_app_front_end/areas/ux/dialogs/dialog_choice_list.dart';

void main() {
  testWidgets('arrows move and enter activates the highlighted row', (
    tester,
  ) async {
    var activated = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DialogChoiceList(
            itemCount: 3,
            onActivate: (i) => activated = i,
            itemBuilder: (context, i, highlighted) => Text('row $i'),
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(activated, 1);
  });

  testWidgets('picker field opens on enter', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppDialogPickerField(
            label: 'Type',
            preview: const SizedBox(width: 8, height: 8),
            valueLabel: 'None',
            onTap: () => opened++,
          ),
        ),
      ),
    );

    Focus.of(tester.element(find.text('None'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(opened, 1);
  });
}
