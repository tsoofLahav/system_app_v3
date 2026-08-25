import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/editor/document_editor_controller.dart';

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

    expect(
      DocumentEditorRegistry.captureMarkedTextForAgent(),
      'the marked span',
    );
  });

  test('captureMarkedTextForAgent stays within the hint budget', () {
    DocumentEditorRegistry.register(
      DocumentEditorController(
        fileId: 1,
        insertAtBlock: (_) async {},
        focusBlock: (_) {},
        flushPendingChanges: () async {},
        markedTextForAgent: () => 'x' * 500,
      ),
    );

    expect(
      DocumentEditorRegistry.captureMarkedTextForAgent()!.length,
      400,
    );
  });
}
