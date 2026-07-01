import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'format_range.dart';
import 'span_text_editing_controller.dart';
import 'text_formatting.dart';

/// Active block text field for context-menu clipboard/format actions.
///
/// See [RICH_TEXT.md]. Keeps a frozen [FormatRange] for the duration of each menu.
class BlockTextFocusRegistry {
  BlockTextFocusRegistry._();

  static TextEditingController? activeController;
  static VoidCallback? onChanged;
  static Map<String, dynamic>? activeBlockContent;
  static FocusNode? activeFocusNode;
  static int? activeBlockId;
  static double baseFontSize = 12.5;

  static int _menuSessionDepth = 0;
  static FormatRange? _frozenRange;
  static final ValueNotifier<int> menuSessionListenable = ValueNotifier(0);

  static bool get hasFocus => activeController != null;
  static bool get isInMenuSession => _menuSessionDepth > 0;
  static FormatRange? get frozenFormatRange => _frozenRange;

  static void register({
    required TextEditingController controller,
    required VoidCallback changed,
    Map<String, dynamic>? blockContent,
    double? fontSize,
    FocusNode? focusNode,
    int? blockId,
  }) {
    activeController = controller;
    onChanged = changed;
    activeBlockContent = blockContent;
    activeFocusNode = focusNode;
    activeBlockId = blockId;
    if (fontSize != null) baseFontSize = fontSize;
  }

  static void unregister(TextEditingController controller) {
    if (_menuSessionDepth > 0) return;
    if (activeController != controller) return;
    activeController = null;
    onChanged = null;
    activeBlockContent = null;
    activeFocusNode = null;
    activeBlockId = null;
  }

  /// Clears focus registry before a structural reload (e.g. block insert).
  static void abandonStashedFocus() {
    activeController = null;
    onChanged = null;
    activeBlockContent = null;
    activeFocusNode = null;
    activeBlockId = null;
  }

  static void openMenuSession() {
    _menuSessionDepth++;
    final controller = activeController;
    if (controller == null) {
      _frozenRange = FormatRange.pending;
    } else {
      _frozenRange = FormatRange.consume(controller.text, controller.selection);
    }
    menuSessionListenable.value++;
  }

  static void closeMenuSession() {
    if (_menuSessionDepth > 0) _menuSessionDepth--;
    FormatRange.clearPending();

    final range = _frozenRange;
    final node = activeFocusNode;
    final controller = activeController;
    _frozenRange = null;
    menuSessionListenable.value++;

    if (_menuSessionDepth != 0 || node == null || controller == null) return;

    final restoreController = controller;
    final restoreNode = node;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (restoreController != activeController) return;
      try {
        if (!restoreNode.hasFocus && restoreNode.canRequestFocus) {
          restoreNode.requestFocus();
        }
        if (range != null && range.isValid) {
          restoreController.selection = TextSelection.collapsed(offset: range.end);
        }
      } catch (_) {
        // Controller or focus node may have been disposed after a reload.
      }
    });
  }

  static FormatRange _effectiveRange(TextEditingController controller) {
    final frozen = _frozenRange;
    if (frozen != null && frozen.isValid) return frozen;
    return FormatRange.resolve(controller.text, controller.selection);
  }

  static Future<void> cut() async {
    final c = activeController;
    if (c == null) return;
    final range = _effectiveRange(c);
    if (!range.isValid) return;
    await Clipboard.setData(
      ClipboardData(text: c.text.substring(range.start, range.end)),
    );
    _replaceSelection('');
  }

  static Future<void> copy() async {
    final c = activeController;
    if (c == null) return;
    final range = _effectiveRange(c);
    if (!range.isValid) return;
    await Clipboard.setData(
      ClipboardData(text: c.text.substring(range.start, range.end)),
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
    final range = _effectiveRange(c);
    if (!range.isValid) return;
    final next = c.text.replaceRange(range.start, range.end, replacement);
    c.value = c.value.copyWith(
      text: next,
      selection: TextSelection.collapsed(
        offset: range.start + replacement.length,
      ),
      composing: TextRange.empty,
    );
    onChanged?.call();
  }

  static void applyTextFormat(String action) {
    final controller = activeController;
    final changed = onChanged;
    if (controller == null || changed == null) return;

    final range = _frozenRange ?? FormatRange.resolve(
      controller.text,
      controller.selection,
    );
    if (!range.isValid) return;

    if (controller is SpanTextEditingController) {
      controller.applyFormatAction(
        action,
        range: range,
        baseFontSize: baseFontSize,
      );
      controller.selection = TextSelection.collapsed(offset: range.end);
      changed();
      return;
    }

    final content = activeBlockContent;
    if (content == null) return;
    final next = applyTextFormatToContent(
      content: content,
      action: action,
      selection: range.selection,
      text: controller.text,
      baseFontSize: baseFontSize,
    );
    activeBlockContent = next;
    changed();
  }
}
