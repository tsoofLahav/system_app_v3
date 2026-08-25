import 'package:super_editor/super_editor.dart';

/// Super Editor IME keys, without Cmd+B / Cmd+I — those belong to the catalog
/// so they toggle once (and so they can expand a collapsed caret to the line).
final List<SuperEditorKeyboardAction> kFileEditorImeKeyboardActions = [
  for (final action in defaultImeKeyboardActions)
    if (action != cmdBToToggleBold && action != cmdIToToggleItalics) action,
];
