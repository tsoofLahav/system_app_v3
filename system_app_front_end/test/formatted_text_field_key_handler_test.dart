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
}
