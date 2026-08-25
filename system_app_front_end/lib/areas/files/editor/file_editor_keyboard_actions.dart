import 'package:super_editor/super_editor.dart';

/// Super Editor IME keys, without Cmd+B / Cmd+I / ⌘V — those belong to the
/// catalog so they toggle once, and so list paste can keep `-` / `1.` points.
final List<SuperEditorKeyboardAction> kFileEditorImeKeyboardActions = [
  for (final action in defaultImeKeyboardActions)
    if (action != cmdBToToggleBold &&
        action != cmdIToToggleItalics &&
        action != pasteWhenCmdVIsPressed)
      action,
];
