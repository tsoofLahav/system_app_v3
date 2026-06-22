import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Tracks the active block text field for unified cut/copy/paste/format menus.
class BlockTextFocusRegistry {
  BlockTextFocusRegistry._();

  static TextEditingController? activeController;
  static VoidCallback? onChanged;
  static ValueChanged<Map<String, dynamic>>? onContentChanged;
  static Map<String, dynamic>? activeContent;

  static void register({
    required TextEditingController controller,
    required VoidCallback changed,
    ValueChanged<Map<String, dynamic>>? contentChanged,
    Map<String, dynamic>? content,
  }) {
    activeController = controller;
    onChanged = changed;
    onContentChanged = contentChanged;
    activeContent = content;
  }

  static void unregister(TextEditingController controller) {
    if (activeController != controller) return;
    activeController = null;
    onChanged = null;
    onContentChanged = null;
    activeContent = null;
  }

  static bool get hasFocus => activeController != null;

  static Future<void> cut() async {
    final c = activeController;
    if (c == null) return;
    final sel = c.selection;
    if (!sel.isValid || sel.isCollapsed) return;
    final text = c.text.substring(sel.start, sel.end);
    await Clipboard.setData(ClipboardData(text: text));
    _replaceSelection('');
  }

  static Future<void> copy() async {
    final c = activeController;
    if (c == null) return;
    final sel = c.selection;
    if (!sel.isValid || sel.isCollapsed) return;
    await Clipboard.setData(
      ClipboardData(text: c.text.substring(sel.start, sel.end)),
    );
  }

  static Future<void> paste() async {
    final c = activeController;
    if (c == null) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null) return;
    _replaceSelection(text);
  }

  static void _replaceSelection(String replacement) {
    final c = activeController;
    if (c == null) return;
    final sel = c.selection;
    if (!sel.isValid) return;
    final next = c.text.replaceRange(sel.start, sel.end, replacement);
    c.value = c.value.copyWith(
      text: next,
      selection: TextSelection.collapsed(offset: sel.start + replacement.length),
      composing: TextRange.empty,
    );
    onChanged?.call();
  }
}
