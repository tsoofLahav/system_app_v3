import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'format_range.dart';
import 'span_text_editing_controller.dart';
import '../../shared/utils/platform_text.dart';
import '../../shared/utils/platform_text.dart';
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

  static int _emojiPickerSessionDepth = 0;
  static _EmojiPickerTarget? _emojiPickerTarget;

  static int _aiInsertSessionDepth = 0;
  static _AiInsertTarget? _aiInsertTarget;
  static _RecentTextTarget? _recentTarget;

  static final ValueNotifier<int> focusListenable = ValueNotifier(0);

  static bool get hasFocus => activeController != null;
  static bool get isInMenuSession => _menuSessionDepth > 0;
  static bool get isInEmojiPickerSession => _emojiPickerSessionDepth > 0;
  static bool get hasEmojiPickerTarget => _emojiPickerTarget != null;
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
    _recentTarget = _RecentTextTarget(
      controller: controller,
      onChanged: changed,
      focusNode: focusNode,
    );
    _bumpFocus();
  }

  static void _bumpFocus() {
    focusListenable.value++;
  }

  static void unregister(TextEditingController controller) {
    if (_menuSessionDepth > 0 ||
        _emojiPickerSessionDepth > 0 ||
        _aiInsertSessionDepth > 0) {
      return;
    }
    if (activeController != controller) return;
    activeController = null;
    onChanged = null;
    activeBlockContent = null;
    activeFocusNode = null;
    activeBlockId = null;
    _bumpFocus();
  }

  /// Clears focus registry before a structural reload (e.g. block insert).
  static void abandonStashedFocus() {
    activeController = null;
    onChanged = null;
    activeBlockContent = null;
    activeFocusNode = null;
    activeBlockId = null;
    _recentTarget = null;
    _bumpFocus();
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

  static void beginEmojiPickerSession() {
    if (_emojiPickerSessionDepth == 0) {
      final controller = activeController;
      final changed = onChanged;
      if (controller == null || changed == null) return;
      _emojiPickerTarget = _EmojiPickerTarget(
        controller: controller,
        onChanged: changed,
        focusNode: activeFocusNode,
        selection: controller.selection,
      );
    }
    if (_emojiPickerTarget == null) return;
    _emojiPickerSessionDepth++;
  }

  static void endEmojiPickerSession() {
    if (_emojiPickerSessionDepth > 0) _emojiPickerSessionDepth--;
    if (_emojiPickerSessionDepth > 0) return;

    final target = _emojiPickerTarget;
    _emojiPickerTarget = null;
    if (target == null) return;

    final restoreController = target.controller;
    final restoreNode = target.focusNode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        if (restoreNode != null &&
            !restoreNode.hasFocus &&
            restoreNode.canRequestFocus) {
          restoreNode.requestFocus();
        }
        final offset = restoreController.selection.baseOffset.clamp(
          0,
          restoreController.text.length,
        );
        restoreController.selection = TextSelection.collapsed(offset: offset);
      } catch (_) {
        // Controller or focus node may have been disposed after a reload.
      }
    });
  }

  static void beginAiInsertSession({int? fallbackInsertOffset}) {
    if (_aiInsertSessionDepth == 0) {
      _aiInsertTarget = _insertTargetForOffset(fallbackInsertOffset);
    }
    if (_aiInsertTarget == null) return;
    _aiInsertSessionDepth++;
  }

  static void endAiInsertSession() {
    if (_aiInsertSessionDepth > 0) _aiInsertSessionDepth--;
    if (_aiInsertSessionDepth > 0) return;

    final target = _aiInsertTarget;
    _aiInsertTarget = null;
    if (target == null) return;

    final restoreController = target.controller;
    final restoreNode = target.focusNode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        if (restoreNode != null &&
            !restoreNode.hasFocus &&
            restoreNode.canRequestFocus) {
          restoreNode.requestFocus();
        }
        restoreController.selection = TextSelection.collapsed(
          offset: target.insertOffset.clamp(0, restoreController.text.length),
        );
      } catch (_) {
        // Controller or focus node may have been disposed after a reload.
      }
    });
  }

  static bool get hasAiInsertTarget => _aiInsertTarget != null;

  static void insertAiEmoji(String text) {
    final target = _aiInsertTarget;
    if (target == null || text.isEmpty) return;
    final index = target.insertOffset.clamp(0, target.controller.text.length);
    _applyInsert(target.controller, target.onChanged, index, index, text);
    target.insertOffset = index + text.length;
  }

  static _AiInsertTarget? _insertTargetForOffset(int? fallbackInsertOffset) {
    final controller = activeController ?? _recentTarget?.controller;
    final changed = onChanged ?? _recentTarget?.onChanged;
    if (controller == null || changed == null) return null;

    final offset = insertOffsetFor(controller) ?? fallbackInsertOffset;
    if (offset == null) return null;

    return _AiInsertTarget(
      controller: controller,
      onChanged: changed,
      focusNode: activeFocusNode ?? _recentTarget?.focusNode,
      insertOffset: offset,
    );
  }

  static int? insertOffsetFor(TextEditingController controller) {
    final selection = controller.selection;
    if (!selection.isValid) return null;
    if (!selection.isCollapsed) {
      return selection.end.clamp(0, controller.text.length);
    }
    return selection.baseOffset.clamp(0, controller.text.length);
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
    await setClipboardText(safeSubstring(c.text, range.start, range.end));
    _replaceSelection('');
  }

  static Future<void> copy() async {
    final c = activeController;
    if (c == null) return;
    final range = _effectiveRange(c);
    if (!range.isValid) return;
    await setClipboardText(safeSubstring(c.text, range.start, range.end));
  }

  static Future<void> paste() async {
    final c = activeController;
    if (c == null) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null) return;
    _replaceSelection(sanitizePlatformText(text));
  }

  static void insertText(String text) {
    if (text.isEmpty) return;

    final target = _emojiPickerTarget;
    final controller = target?.controller ?? activeController;
    final changed = target?.onChanged ?? onChanged;
    if (controller == null || changed == null) return;

    final selection = target?.selection ?? controller.selection;
    final start = selection.start.clamp(0, controller.text.length);
    final end = selection.end.clamp(0, controller.text.length);
    _applyInsert(controller, changed, start, end, text);
  }

  static String? markedText() {
    final controller = activeController;
    if (controller == null) return null;
    final selection = controller.selection;
    if (!selection.isValid || selection.isCollapsed) return null;
    final start = selection.start.clamp(0, controller.text.length);
    final end = selection.end.clamp(0, controller.text.length);
    if (end <= start) return null;
    final text = safeSubstring(controller.text, start, end).trim();
    return text.isEmpty ? null : text;
  }

  static int? markInsertOffset() {
    final controller = activeController;
    if (controller == null) return null;
    final selection = controller.selection;
    if (!selection.isValid || selection.isCollapsed) return null;
    return selection.end.clamp(0, controller.text.length);
  }

  /// Caret after a highlight, or at the caret when suggesting from a line.
  static int? emojiInsertOffset() {
    final controller = activeController ?? _recentTarget?.controller;
    if (controller == null) return null;
    return insertOffsetFor(controller);
  }

  static bool get hasMarkedText => markedText() != null;

  static void insertTextAtOffset(int offset, String text) {
    if (text.isEmpty) return;
    if (_aiInsertTarget != null) {
      insertAiEmoji(text);
      return;
    }
    final controller = activeController ?? _recentTarget?.controller;
    final changed = onChanged ?? _recentTarget?.onChanged;
    if (controller == null || changed == null) return;
    final index = offset.clamp(0, controller.text.length);
    _applyInsert(controller, changed, index, index, text);
  }

  static void _applyInsert(
    TextEditingController controller,
    VoidCallback changed,
    int start,
    int end,
    String text,
  ) {
    final safeText = sanitizePlatformText(text);
    if (safeText.isEmpty) return;
    final (rangeStart, rangeEnd) =
        normalizeUtf16Range(controller.text, start, end);
    final next = controller.text.replaceRange(rangeStart, rangeEnd, safeText);
    controller.value = controller.value.copyWith(
      text: sanitizePlatformText(next),
      selection: TextSelection.collapsed(offset: rangeStart + safeText.length),
      composing: TextRange.empty,
    );
    if (controller is SpanTextEditingController) {
      controller.ensureSpansMatchText();
    }
    changed();
  }

  static void _replaceSelection(String replacement) {
    final c = activeController;
    final changed = onChanged;
    if (c == null || changed == null) return;
    final range = _effectiveRange(c);
    if (!range.isValid) return;
    _applyInsert(c, changed, range.start, range.end, replacement);
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

class _EmojiPickerTarget {
  const _EmojiPickerTarget({
    required this.controller,
    required this.onChanged,
    required this.focusNode,
    required this.selection,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;
  final FocusNode? focusNode;
  final TextSelection selection;
}

class _RecentTextTarget {
  const _RecentTextTarget({
    required this.controller,
    required this.onChanged,
    required this.focusNode,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;
  final FocusNode? focusNode;
}

class _AiInsertTarget {
  _AiInsertTarget({
    required this.controller,
    required this.onChanged,
    required this.focusNode,
    required this.insertOffset,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;
  final FocusNode? focusNode;
  int insertOffset;
}
