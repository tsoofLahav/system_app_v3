import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/editor/document_editor_controller.dart';
import 'package:system_app_front_end/core/l10n/app_strings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    DocumentEditorRegistry.unregister(1);
  });

  test('captureMarkedTextForAgent freezes the active editor mark', () {
    DocumentEditorRegistry.register(
      DocumentEditorController(
        fileId: 1,
        insertAtBlock: (_) async {},
        focusBlock: (_) {},
        flushPendingChanges: () async {},
        markedTextForAgent: () => '  the marked span  ',
      ),
    );

    final mark = DocumentEditorRegistry.captureMarkedTextForAgent();
    expect(mark?.text, 'the marked span');
    expect(mark?.truncated, isFalse);
  });

  test('captureMarkedTextForAgent stays within the hint budget', () {
    DocumentEditorRegistry.register(
      DocumentEditorController(
        fileId: 1,
        insertAtBlock: (_) async {},
        focusBlock: (_) {},
        flushPendingChanges: () async {},
        markedTextForAgent: () =>
            'x' * (DocumentEditorRegistry.agentSelectedTextMaxChars + 80),
      ),
    );

    final mark = DocumentEditorRegistry.captureMarkedTextForAgent();
    expect(
      mark!.text.length,
      DocumentEditorRegistry.agentSelectedTextMaxChars,
    );
    expect(mark.truncated, isTrue);
  });

  test('marked-text truncation copy states the budget', () {
    expect(
      AppStrings.en.markedTextTruncated(
        DocumentEditorRegistry.agentSelectedTextMaxChars,
      ),
      contains('${DocumentEditorRegistry.agentSelectedTextMaxChars}'),
    );
    expect(
      AppStrings.he.markedTextTruncated(
        DocumentEditorRegistry.agentSelectedTextMaxChars,
      ),
      contains('${DocumentEditorRegistry.agentSelectedTextMaxChars}'),
    );
  });
}
