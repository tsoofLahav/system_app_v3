import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/editor/file_preview.dart';

void main() {
  testWidgets('file preview draws the document, not marker fences', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FilePreview(
            agentText: '# Hello\n\nA paragraph.\n\n[INFO id="9"]\nNote title\nThe body\n[/INFO]',
          ),
        ),
      ),
    );

    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('A paragraph.'), findsOneWidget);
    expect(find.text('Note title'), findsOneWidget);
    expect(find.textContaining('[INFO'), findsNothing);
    expect(find.textContaining('%%system_app'), findsNothing);
    expect(find.textContaining('id="9"'), findsNothing);
  });

  testWidgets('a leftover structure marker is a rule, not the fence text',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FilePreview(agentText: '[BULLET_LIST]'),
        ),
      ),
    );

    expect(find.text('[BULLET_LIST]'), findsNothing);
  });
}
