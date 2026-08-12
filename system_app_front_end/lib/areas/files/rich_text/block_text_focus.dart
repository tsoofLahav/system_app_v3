import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import './format_range.dart';
import './span_text_editing_controller.dart';
import '../../../shared/utils/platform_text.dart';
import '../editor/document_mark.dart';
import '../editor/document_text_flow.dart';
import './text_formatting.dart';

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

  /// The flow of the editor the caret is in, when there is one. Its presence is
  /// what lets actions reach across parts.
  static DocumentTextFlow? activeFlow;

  static int _menuSessionDepth = 0;
  static FormatRange? _frozenRange;
  static DocumentMark? _frozenMark;

  /// True when the menu opened on a real non-collapsed selection (not line-at-caret).
  static var _pendingExplicitSelection = false;
  static var _frozenExplicitSelection = false;
  static DocumentMark? _pendingMark;
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

  /// The mark an open menu will act on, frozen when the menu opened.
  static DocumentMark? get frozenMark => _frozenMark;

  /// True when the frozen mark came from a real non-collapsed selection.
  static bool get frozenWasExplicitSelection => _frozenExplicitSelection;

  /// The single target for any action: the current selection, or the line at
  /// the caret when nothing is marked.
  ///
  /// Every action must go through this — see [DocumentMark]. While a menu is
  /// open the mark frozen at open time wins, so the target cannot shift under
  /// the user mid-menu.
  static DocumentMark resolveMark() {
    final frozen = _frozenMark;
    if (frozen != null && frozen.isValid) return frozen;
    final pending = _pendingMark;
    if (pending != null && pending.isValid) return pending;
    return _resolveLiveMark();
  }

  static DocumentMark _resolveLiveMark() {
    final flow = activeFlow;
    if (flow != null) {
      final mark = DocumentMark.resolve(flow);
      if (mark.isValid) return mark;
    }

    final controller = activeController ?? _recentTarget?.controller;
    if (controller == null) return const DocumentMark.empty();
    return DocumentMark.resolveForController(
      controller,
      onChanged: onChanged ?? _recentTarget?.onChanged,
    );
  }

  /// Captured on secondary pointer-down, before opening the menu can disturb
  /// focus or collapse the selection.
  static void capturePendingMark() {
    if (_pendingMark != null && _pendingMark!.isValid) return;
    final controller = activeController ?? _recentTarget?.controller;
    final sel = controller?.selection;
    _pendingExplicitSelection =
        sel != null && sel.isValid && !sel.isCollapsed;
    _pendingMark = _resolveLiveMark();
  }

  static void clearPendingMark() => _pendingMark = null;

  static void register({
    required TextEditingController controller,
    required VoidCallback changed,
    Map<String, dynamic>? blockContent,
    double? fontSize,
    FocusNode? focusNode,
    int? blockId,
    DocumentTextFlow? flow,
  }) {
    activeController = controller;
    onChanged = changed;
    activeBlockContent = blockContent;
    activeFocusNode = focusNode;
    activeBlockId = blockId;
    activeFlow = flow;
    if (fontSize != null) baseFontSize = fontSize;
    _recentTarget = _RecentTextTarget(
      controller: controller,
      onChanged: changed,
      focusNode: focusNode,
    );
    _bumpFocus();
  }

  static void _bumpFocus() {
    // Defer so listeners (e.g. AppShortcutsScope) are not rebuilt while the
    // widget tree is locked during dispose/unmount (task reorder, block reload).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      focusListenable.value++;
    });
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
    activeFlow = null;
    _recentTarget = null;
    _frozenMark = null;
    _pendingMark = null;
    _bumpFocus();
  }

  static void openMenuSession() {
    _menuSessionDepth++;
    _frozenExplicitSelection = _pendingExplicitSelection;
    _pendingExplicitSelection = false;
    _frozenMark = _pendingMark ?? _resolveLiveMark();
    _pendingMark = null;
    final controller = activeController;
    if (controller == null) {
      _frozenRange = FormatRange.pending;
    } else {
      _frozenRange = FormatRange.consume(controller.text, controller.selection);
    }
    // Collapsed right-click: keep line-at-caret for format actions, but do not
    // paint a fake text mark (needed for object-level info linking).
    if (!_frozenExplicitSelection) {
      _frozenRange = null;
    }
    menuSessionListenable.value++;
  }

  static void closeMenuSession() {
    if (_menuSessionDepth > 0) _menuSessionDepth--;
    FormatRange.clearPending();

    final range = _frozenRange;
    final node = activeFocusNode;
    final controller = activeController;
    final mark = _frozenMark;
    _frozenRange = null;
    _frozenMark = null;
    _pendingMark = null;
    _frozenExplicitSelection = false;
    menuSessionListenable.value++;

    // A mark that covered several parts stays marked after the menu closes, so
    // the caret is not silently yanked into one of them.
    if (mark != null && mark.spansParts) return;

    if (_menuSessionDepth != 0 || node == null || controller == null) return;

    final restoreController = controller;
    final restoreNode = node;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (restoreController != activeController) return;
      try {
        if (restoreNode.context != null &&
            !restoreNode.hasFocus &&
            restoreNode.canRequestFocus) {
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
            restoreNode.context != null &&
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
            restoreNode.context != null &&
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

  static void insertAiText(String text) {
    insertAiEmoji(text);
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

  static Future<void> cut() async {
    final mark = resolveMark();
    if (!mark.isValid) return;
    await setClipboardText(mark.text);
    final fullyCovered = mark.fullyCoveredSegmentIds;
    mark.delete();
    _afterMarkEdit(mark, fullyCovered: fullyCovered);
  }

  static Future<void> copy() async {
    final mark = resolveMark();
    if (!mark.isValid) return;
    await setClipboardText(mark.text);
  }

  static Future<void> paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null) return;
    final mark = resolveMark();
    if (mark.spans.isEmpty) return;
    // Pasting over parts that were marked in full replaces them, so the emptied
    // structures should go the same way as for a cut.
    final fullyCovered = mark.fullyCoveredSegmentIds;
    mark.replaceWith(sanitizePlatformText(text));
    _afterMarkEdit(mark, fullyCovered: fullyCovered, keepFirstPart: true);
  }

  /// After an edit the old mark no longer describes anything, so the caret is
  /// left collapsed where the edit happened and any structure that was fully
  /// consumed is dropped.
  static void _afterMarkEdit(
    DocumentMark mark, {
    Set<String> fullyCovered = const {},
    bool keepFirstPart = false,
  }) {
    if (!mark.spansParts) return;
    _frozenMark = null;
    final flow = activeFlow;
    flow?.clearSelection();
    final prunable = {...fullyCovered};
    if (keepFirstPart) {
      // Paste leaves its text in the first part, so that part must survive.
      prunable.remove(mark.first?.segmentId);
    }
    flow?.pruneStructures(prunable, spansParts: true);
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

  /// Text an action will run on: what is marked, or the caret's line.
  ///
  /// This is the text AI actions should be given.
  static String? markedText() {
    final mark = resolveMark();
    if (!mark.isValid) return null;
    final text = mark.text.trim();
    return text.isEmpty ? null : text;
  }

  /// Offset just after the mark, in the mark's last part.
  static int? markInsertOffset() {
    final mark = resolveMark();
    if (!mark.isValid) return null;
    return mark.spans.last.safeEnd;
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

  static void applyTextFormat(String action) {
    final mark = resolveMark();

    // Formatting spans the whole mark, so it reaches every part the user marked.
    if (mark.isValid && mark.spans.any((s) => s.spanController != null)) {
      try {
        mark.applyFormat(action, baseFontSize: baseFontSize);
      } catch (_) {
        return;
      }
      if (!mark.spansParts) {
        final span = mark.spans.first;
        span.controller.selection =
            TextSelection.collapsed(offset: span.safeEnd);
      }
      return;
    }

    final controller = activeController;
    final changed = onChanged;
    if (controller == null || changed == null) return;

    final range = _frozenRange ??
        FormatRange.resolve(controller.text, controller.selection);
    if (!range.isValid) return;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        changed();
      } catch (_) {}
    });
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
