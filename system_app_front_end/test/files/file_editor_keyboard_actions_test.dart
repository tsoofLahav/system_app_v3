import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:system_app_front_end/areas/files/editor/file_editor_keyboard_actions.dart';

void main() {
  test('file editor IME keys omit Super Editor Cmd+B, Cmd+I and Cmd+V', () {
    expect(kFileEditorImeKeyboardActions, isNot(contains(cmdBToToggleBold)));
    expect(kFileEditorImeKeyboardActions, isNot(contains(cmdIToToggleItalics)));
    expect(
      kFileEditorImeKeyboardActions,
      isNot(contains(pasteWhenCmdVIsPressed)),
    );
    expect(defaultImeKeyboardActions, contains(pasteWhenCmdVIsPressed));
    expect(defaultImeKeyboardActions, contains(cmdBToToggleBold));
    expect(defaultImeKeyboardActions, contains(cmdIToToggleItalics));
    expect(
      kFileEditorImeKeyboardActions.length,
      defaultImeKeyboardActions.length - 3,
    );
  });
}
