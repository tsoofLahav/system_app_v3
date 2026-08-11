import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../../shared/utils/platform_text.dart';
import '../editor/document_text_flow.dart';
import './block_text_focus.dart';
import './format_range.dart';
import './frozen_selection_painter.dart';
import './rtl/rtl.dart';
import './span_text_editing_controller.dart';
import './text_emoji_picker.dart';

/// Text field that registers for block context-menu clipboard/format actions.
class DescriptionTextRange {
  const DescriptionTextRange({
    required this.start,
    required this.end,
    required this.link,
  });

  final int start;
  final int end;
  final Map<String, dynamic> link;
}

class FormattedTextField extends StatefulWidget {
  const FormattedTextField({
    super.key,
    required this.controller,
    required this.style,
    this.blockContent,
    this.hintText,
    this.maxLines,
    this.minLines = 1,
    this.onChanged,
    this.onSubmitted,
    this.onBackspaceAtStart,
    this.onSelectAll,
    this.onPaste,
    this.textInputAction,
    this.focusNode,
    this.onEnter,
    this.stripNewlines = false,
    this.onSecondaryTapDown,
    this.textAlignVertical,
    this.blockId,
    this.segmentId,
    this.documentBaseOffset = 0,
    this.emojiSearchHint = 'Search emoji',
    this.emojiPickerTitle = 'Insert emoji…',
    this.descriptionRanges = const [],
    this.onDescriptionHover,
    this.onDescriptionDoubleTap,
    this.onArrowExitAbove,
    this.onArrowExitBelow,
  });

  final TextEditingController controller;
  final TextStyle style;
  final Map<String, dynamic>? blockContent;
  final String? hintText;
  final int? maxLines;
  final int minLines;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Future<void> Function()? onBackspaceAtStart;
  final VoidCallback? onSelectAll;
  final Future<void> Function(String text)? onPaste;
  final TextInputAction? textInputAction;
  final FocusNode? focusNode;
  final VoidCallback? onEnter;
  final bool stripNewlines;
  final GestureTapDownCallback? onSecondaryTapDown;
  final TextAlignVertical? textAlignVertical;
  final int? blockId;

  /// Position of this field in the document-wide text flow. When set (and a
  /// [DocumentTextFlowScope] is above), arrow keys and selection cross out of
  /// this field into neighbouring paragraphs, bullets and cells.
  final String? segmentId;

  /// Absolute start of this field's slice in the marker-text buffer.
  final int documentBaseOffset;

  /// When there is no [DocumentTextFlow] (Super Editor body), ↑ on the first
  /// visual line calls this so the host can leave the embed.
  final VoidCallback? onArrowExitAbove;

  /// When there is no [DocumentTextFlow], ↓ on the last visual line calls this.
  final VoidCallback? onArrowExitBelow;

  final String emojiSearchHint;
  final String emojiPickerTitle;

  final List<DescriptionTextRange> descriptionRanges;
  final ValueChanged<DescriptionTextRange?>? onDescriptionHover;
  final ValueChanged<DescriptionTextRange>? onDescriptionDoubleTap;

  @override
  State<FormattedTextField> createState() => _FormattedTextFieldState();
}

class _FormattedTextFieldState extends State<FormattedTextField> {
  late FocusNode _focusNode;
  bool _ownsFocus = false;
  bool _normalizingSelection = false;
  FocusOnKeyEventCallback? _editableKeyHandler;
  DocumentTextFlow? _flow;
  String? _registeredSegmentId;
  int? _registeredBaseOffset;
  bool _applyingFlowSelection = false;
  TextDirection? _detectedDirection;
  Offset? _pendingTapGlobal;
  // Built once: the overrides are stateless, so they can outlive a rebuild.
  final _rtlMotionActions = rtlCaretMotionActions();

  @override
  void initState() {
    super.initState();
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
    } else {
      _focusNode = FocusNode();
      _ownsFocus = true;
    }
    _focusNode.addListener(_onFocusChanged);
    widget.controller.addListener(_normalizeSelectionIfNeeded);
    widget.controller.addListener(_syncFlowFromLocalSelection);
    widget.controller.addListener(_syncParagraphDirection);
    _detectedDirection = detectParagraphTextDirection(widget.controller.text);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureKeyHandlerChained());
  }

  /// RTL solution: keep [TextField.textDirection] on the first strong character
  /// (see `rtl/RTL.md`).
  void _syncParagraphDirection() {
    final next = detectParagraphTextDirection(widget.controller.text);
    if (next == _detectedDirection) return;
    setState(() => _detectedDirection = next);
  }

  TextDirection _resolvedTextDirection(BuildContext context) {
    return resolveFieldTextDirection(
      widget.controller.text,
      Directionality.of(context),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attachToFlow(DocumentTextFlowScope.maybeOf(context));
  }

  void _attachToFlow(DocumentTextFlow? flow) {
    final segmentId = widget.segmentId;
    final base = widget.documentBaseOffset;
    final changed = flow != _flow ||
        segmentId != _registeredSegmentId ||
        base != _registeredBaseOffset;
    if (!changed) return;

    final previousId = _registeredSegmentId;
    if (previousId != null) {
      _flow?.unregister(previousId, widget.controller);
    }
    _flow = flow;
    _registeredSegmentId = segmentId;
    _registeredBaseOffset = base;
    if (flow != null && segmentId != null) {
      flow.register(
        segmentId,
        widget.controller,
        _focusNode,
        onChanged: _notifyChanged,
        baseOffset: base,
      );
    }
  }

  /// Keeps the document selection in step with ordinary in-field selection, so
  /// that an anchor already exists when the user shift-arrows past the edge.
  /// A selection that already spans segments cannot be represented by one
  /// field, so it is left alone.
  void _syncFlowFromLocalSelection() {
    final flow = _flow;
    final segmentId = _registeredSegmentId;
    if (flow == null || segmentId == null) return;
    if (_applyingFlowSelection) return;
    if (!_focusNode.hasFocus) return;
    if (flow.spansSegments) return;

    final selection = widget.controller.selection;
    if (!selection.isValid) return;
    flow.collapseTo(DocumentTextPosition(segmentId, selection.baseOffset));
    if (!selection.isCollapsed) {
      flow.extendTo(DocumentTextPosition(segmentId, selection.extentOffset));
    }
  }

  @override
  void didUpdateWidget(covariant FormattedTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_normalizeSelectionIfNeeded);
      oldWidget.controller.removeListener(_syncFlowFromLocalSelection);
      oldWidget.controller.removeListener(_syncParagraphDirection);
      widget.controller.addListener(_normalizeSelectionIfNeeded);
      widget.controller.addListener(_syncFlowFromLocalSelection);
      widget.controller.addListener(_syncParagraphDirection);
      _detectedDirection = detectParagraphTextDirection(widget.controller.text);
      final previousId = _registeredSegmentId;
      if (previousId != null) _flow?.unregister(previousId, oldWidget.controller);
      _registeredSegmentId = null;
      _registeredBaseOffset = null;
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_onFocusChanged);
      if (_ownsFocus) {
        _focusNode.dispose();
        _ownsFocus = false;
      }
      if (widget.focusNode != null) {
        _focusNode = widget.focusNode!;
      } else {
        _focusNode = FocusNode();
        _ownsFocus = true;
      }
      _focusNode.addListener(_onFocusChanged);
    }
    _attachToFlow(_flow);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureKeyHandlerChained());
  }

  @override
  void dispose() {
    if (_focusNode.onKeyEvent == _chainedKeyHandler) {
      _focusNode.onKeyEvent = _editableKeyHandler;
    }
    final registeredId = _registeredSegmentId;
    if (registeredId != null) _flow?.unregister(registeredId, widget.controller);
    widget.controller.removeListener(_normalizeSelectionIfNeeded);
    widget.controller.removeListener(_syncFlowFromLocalSelection);
    widget.controller.removeListener(_syncParagraphDirection);
    _focusNode.removeListener(_onFocusChanged);
    BlockTextFocusRegistry.unregister(widget.controller);
    if (_ownsFocus) _focusNode.dispose();
    super.dispose();
  }

  void _ensureKeyHandlerChained() {
    if (!mounted) return;
    final current = _focusNode.onKeyEvent;
    if (current == _chainedKeyHandler) return;
    _editableKeyHandler = current;
    _focusNode.onKeyEvent = _chainedKeyHandler;
  }

  KeyEventResult _chainedKeyHandler(FocusNode node, KeyEvent event) {
    final result = _onFocusKeyEvent(node, event);
    if (result == KeyEventResult.handled) return result;
    final editable = _editableKeyHandler;
    if (editable != null && editable != _chainedKeyHandler) {
      return editable(node, event);
    }
    return KeyEventResult.ignored;
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      BlockTextFocusRegistry.register(
        controller: widget.controller,
        changed: _notifyChanged,
        blockContent: widget.blockContent,
        fontSize: widget.style.fontSize ?? 12.5,
        focusNode: _focusNode,
        blockId: widget.blockId,
        flow: _flow,
      );
      // File pane owns scrolling — keep the caret in view without letting each
      // EditableText scroll as its own surface.
      _ensureVisibleInFilePane();
    } else {
      if ((BlockTextFocusRegistry.isInMenuSession ||
              BlockTextFocusRegistry.isInEmojiPickerSession) &&
          BlockTextFocusRegistry.activeController == widget.controller) {
        return;
      }
      BlockTextFocusRegistry.unregister(widget.controller);
    }
  }

  void _ensureVisibleInFilePane() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focusNode.hasFocus) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.15,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    });
  }

  void _notifyChanged() {
    final controller = widget.controller;
    if (controller is SpanTextEditingController) {
      controller.ensureSpansMatchText();
    }
    widget.onChanged?.call(controller.text);
  }

  void _normalizeSelectionIfNeeded() {
    if (_normalizingSelection) return;
    final controller = widget.controller;
    final normalized = normalizeTextSelection(controller.text, controller.selection);
    if (normalized == controller.selection) return;
    _normalizingSelection = true;
    controller.selection = normalized;
    _normalizingSelection = false;
  }

  Future<void> _copySelection() async {
    final flow = _flow;
    if (flow != null && flow.spansSegments) {
      final text = flow.selectedText();
      if (text.isNotEmpty) await setClipboardText(text);
      return;
    }
    final controller = widget.controller;
    final selection = controller.selection;
    if (!selection.isValid || selection.isCollapsed) return;
    await setClipboardText(
      safeSubstring(controller.text, selection.start, selection.end),
    );
  }

  Future<void> _cutSelection() async {
    final flow = _flow;
    if (flow != null && flow.spansSegments) {
      final text = flow.selectedText();
      if (text.isNotEmpty) await setClipboardText(text);
      flow.deleteSelection();
      return;
    }
    if (_selectionCoversEntireField()) {
      final copied = widget.controller.text;
      if (copied.isNotEmpty) await setClipboardText(copied);
      _clearEntireFieldAndPruneStructure();
      return;
    }
    final controller = widget.controller;
    final selection = controller.selection;
    if (!selection.isValid || selection.isCollapsed) return;
    final copied = safeSubstring(
      controller.text,
      selection.start,
      selection.end,
    );
    if (copied.isEmpty) return;
    await setClipboardText(copied);
    final (start, end) = normalizeUtf16Range(
      controller.text,
      selection.start,
      selection.end,
    );
    final next = sanitizePlatformText(
      controller.text.replaceRange(start, end, ''),
    );
    controller.value = controller.value.copyWith(
      text: next,
      selection: TextSelection.collapsed(offset: start),
      composing: TextRange.empty,
    );
    if (controller is SpanTextEditingController) {
      controller.ensureSpansMatchText();
    }
    _notifyChanged();
  }

  KeyEventResult _onFocusKeyEvent(FocusNode node, KeyEvent event) {
    if (!_focusNode.hasFocus) return KeyEventResult.ignored;

    // A held-down arrow arrives as repeat events. They have to go through the
    // same handler as the first press, or the caret would revert to the text
    // field's own idea of direction halfway through a long press.
    if (event is KeyRepeatEvent) {
      return _handleFlowArrowKey(event)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isMeta = HardwareKeyboard.instance.isMetaPressed;
    if (isMeta && event.logicalKey == LogicalKeyboardKey.keyE &&
        HardwareKeyboard.instance.isShiftPressed) {
      _openEmojiPicker();
      return KeyEventResult.handled;
    }

    if (isMeta && !HardwareKeyboard.instance.isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyC) {
      _copySelection();
      return KeyEventResult.handled;
    }

    if (isMeta && !HardwareKeyboard.instance.isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyX) {
      _cutSelection();
      return KeyEventResult.handled;
    }

    if (isMeta && event.logicalKey == LogicalKeyboardKey.keyA) {
      widget.onSelectAll?.call();
      final flow = _flow;
      if (flow != null && flow.order.length > 1) {
        flow.selectAll();
        return KeyEventResult.handled;
      }
      widget.controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.controller.text.length,
      );
      return KeyEventResult.handled;
    }

    if (_handleKeyOverSpanningSelection(event)) return KeyEventResult.handled;

    if (_handleFlowArrowKey(event)) return KeyEventResult.handled;

    if (event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed &&
        widget.onEnter != null) {
      widget.onEnter!();
      return KeyEventResult.handled;
    }

    if ((event.logicalKey == LogicalKeyboardKey.backspace ||
            event.logicalKey == LogicalKeyboardKey.delete) &&
        _selectionCoversEntireField()) {
      if (_clearEntireFieldAndPruneStructure()) {
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        _shouldInvokeBackspaceAtStart() &&
        widget.onBackspaceAtStart != null) {
      unawaited(widget.onBackspaceAtStart!());
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// True when the field's selection covers every character (Cmd+A style).
  bool _selectionCoversEntireField() {
    final text = widget.controller.text;
    if (text.isEmpty) return false;
    final selection = widget.controller.selection;
    if (!selection.isValid || selection.isCollapsed) return false;
    final start = selection.start < selection.end ? selection.start : selection.end;
    final end = selection.start < selection.end ? selection.end : selection.start;
    return start == 0 && end == text.length;
  }

  /// Clears this field and, for list/table/embed parts, removes the structure
  /// the way deleting a marked line would — so objects feel like part of the
  /// text, not a separate widget. Plain paragraphs are only cleared.
  bool _clearEntireFieldAndPruneStructure() {
    final text = widget.controller.text;
    if (text.isEmpty) return false;

    widget.controller.value = widget.controller.value.copyWith(
      text: '',
      selection: const TextSelection.collapsed(offset: 0),
      composing: TextRange.empty,
    );
    if (widget.controller is SpanTextEditingController) {
      (widget.controller as SpanTextEditingController).ensureSpansMatchText();
    }
    _notifyChanged();

    final segmentId = _registeredSegmentId;
    final flow = _flow;
    // Structure parts have `#` in the id; plain paragraphs do not.
    if (segmentId == null || flow == null || !segmentId.contains('#')) {
      return true;
    }

    final toPrune = <String>{segmentId};
    _expandPruneToWholeStructureIfEmpty(flow, segmentId, toPrune);
    flow.pruneStructures(toPrune, spansParts: toPrune.length > 1);
    return true;
  }

  /// When clearing one part leaves a list/table/info with no content left,
  /// mark every part so prune removes the whole structure.
  void _expandPruneToWholeStructureIfEmpty(
    DocumentTextFlow flow,
    String segmentId,
    Set<String> toPrune,
  ) {
    // Unified info text is one segment — clearing it empties the object.
    if (segmentId.endsWith('#infoText')) return;

    const titleSuffix = '#infoTitle';
    const bodySuffix = '#infoBody';
    if (segmentId.endsWith(titleSuffix)) {
      final bodyId =
          '${segmentId.substring(0, segmentId.length - titleSuffix.length)}$bodySuffix';
      final body = flow.controllerFor(bodyId);
      if (body != null && body.text.isEmpty) toPrune.add(bodyId);
      return;
    }
    if (segmentId.endsWith(bodySuffix)) {
      final titleId =
          '${segmentId.substring(0, segmentId.length - bodySuffix.length)}$titleSuffix';
      final title = flow.controllerFor(titleId);
      if (title != null && title.text.isEmpty) toPrune.add(titleId);
      return;
    }

    final hash = segmentId.indexOf('#');
    if (hash < 0) return;
    final blockId = segmentId.substring(0, hash);
    final suffix = segmentId.substring(hash);

    // List bullets: `#iN` — if every bullet is empty, drop them all.
    if (RegExp(r'^#i\d+$').hasMatch(suffix)) {
      final ids = [
        for (final id in flow.order)
          if (id.startsWith('$blockId#i')) id,
      ];
      if (_allSegmentsEmpty(flow, ids, toPrune)) toPrune.addAll(ids);
      return;
    }

    // Table cells: `#cR:C` — if every cell is empty, drop the table.
    if (RegExp(r'^#c\d+:\d+$').hasMatch(suffix)) {
      final ids = [
        for (final id in flow.order)
          if (id.startsWith('$blockId#c')) id,
      ];
      if (_allSegmentsEmpty(flow, ids, toPrune)) toPrune.addAll(ids);
      return;
    }

    // Task rows: `#tN` — if every task is empty, drop them all (host removes
    // the object when no tasks remain).
    if (RegExp(r'^#t\d+$').hasMatch(suffix)) {
      final ids = [
        for (final id in flow.order)
          if (id.startsWith('$blockId#t')) id,
      ];
      if (_allSegmentsEmpty(flow, ids, toPrune)) toPrune.addAll(ids);
    }
  }

  bool _allSegmentsEmpty(
    DocumentTextFlow flow,
    List<String> ids,
    Set<String> alreadyCleared,
  ) {
    if (ids.isEmpty) return false;
    for (final id in ids) {
      if (alreadyCleared.contains(id)) continue;
      if ((flow.controllerFor(id)?.text ?? '').trim().isNotEmpty) return false;
    }
    return true;
  }

  /// This field's share of the mark an open menu will act on, so the user sees
  /// exactly what the action will hit — across every part it covers.
  ///
  /// When a [DocumentMark] is frozen, only that mark is painted — never also
  /// fall back to [FormatRange], which can expand a caret to a whole line and
  /// show a second highlight next to the user's selection.
  TextSelection? _frozenMarkRange() {
    final mark = BlockTextFocusRegistry.frozenMark;
    if (mark != null) {
      if (!mark.isValid) return null;
      for (final span in mark.spans) {
        if (span.controller != widget.controller || span.isEmpty) continue;
        return span.selection;
      }
      return null;
    }

    // Lone field outside a document flow: FormatRange is the only frozen target.
    final frozenRange = BlockTextFocusRegistry.frozenFormatRange;
    if (frozenRange == null || !frozenRange.isValid) return null;
    if (BlockTextFocusRegistry.activeController != widget.controller) return null;
    return frozenRange.selection;
  }

  /// Right-clicking outside an existing mark moves the caret here first, so the
  /// action targets the line the user pointed at rather than a stale mark
  /// somewhere else in the file.
  void _capturePendingMark() {
    final flow = _flow;
    final segmentId = _registeredSegmentId;
    if (flow != null && segmentId != null) {
      final marked = flow.selectionWithin(segmentId);
      final pointsInsideMark = marked != null;
      if (!pointsInsideMark && flow.spansSegments) {
        flow.clearSelection();
      }
      if (!flow.spansSegments && !_focusNode.hasFocus) {
        BlockTextFocusRegistry.register(
          controller: widget.controller,
          changed: _notifyChanged,
          blockContent: widget.blockContent,
          fontSize: widget.style.fontSize ?? 12.5,
          focusNode: _focusNode,
          blockId: widget.blockId,
          flow: flow,
        );
      }
    }
    BlockTextFocusRegistry.capturePendingMark();
  }

  /// Shift+click extends the document selection into this part; a plain click
  /// drops a selection that was covering several parts.
  ///
  /// RTL solution (`rtl/RTL.md`): empty-padding taps → logical line end in this
  /// same `onTap` turn; glyph taps keep Flutter's hit-test.
  void _handleTap() {
    final flow = _flow;
    final segmentId = _registeredSegmentId;
    final tapGlobal = _pendingTapGlobal;
    _pendingTapGlobal = null;

    var offset = widget.controller.selection.isValid
        ? widget.controller.selection.extentOffset
        : widget.controller.text.length;

    if (tapGlobal != null) {
      final host = context.findRenderObject();
      final editable = host == null ? null : _findRenderEditable(host);
      if (editable != null) {
        final corrected = emptySpaceCaretOffset(
          editable: editable,
          globalPosition: tapGlobal,
          textLength: widget.controller.text.length,
        );
        if (corrected != null) {
          offset = corrected;
          widget.controller.selection = collapsedAtLogicalEnd(corrected);
          if (flow != null && segmentId != null) {
            flow.collapseTo(DocumentTextPosition(segmentId, corrected));
          }
        }
      }
    }

    if (flow == null || segmentId == null) return;
    if (!widget.controller.selection.isValid) return;

    if (HardwareKeyboard.instance.isShiftPressed && flow.selection != null) {
      _applyFlowSelection(
        flow,
        DocumentTextPosition(segmentId, offset),
        extend: true,
      );
    } else if (flow.spansSegments) {
      _applyFlowSelection(
        flow,
        DocumentTextPosition(segmentId, offset),
        extend: false,
      );
    }
  }

  /// Deletes or replaces a selection that covers several parts, before the text
  /// field can act on its own share of it.
  ///
  /// Enter only clears the selection: splitting is left to a second press, so
  /// the split always happens at a caret in a known part.
  bool _handleKeyOverSpanningSelection(KeyEvent event) {
    final flow = _flow;
    if (flow == null || !flow.spansSegments) return false;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.enter) {
      flow.deleteSelection();
      return true;
    }

    if (HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed) {
      return false;
    }

    final character = event.character;
    if (character == null || character.isEmpty) return false;
    if (key == LogicalKeyboardKey.tab || key == LogicalKeyboardKey.escape) {
      return false;
    }

    final start = flow.orderedSelection()?.$1;
    flow.deleteSelection();
    if (start != null) flow.insertTextAt(start, character);
    return true;
  }

  /// Moves the caret out of this field when an arrow key runs past its edge.
  ///
  /// Anything that stays inside the field is left to the text field itself, so
  /// normal within-part movement is untouched.
  bool _handleFlowArrowKey(KeyEvent event) {
    final flow = _flow;
    final segmentId = _registeredSegmentId;

    final key = event.logicalKey;
    final isHorizontal = key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight;
    final isVertical = key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown;
    if (!isHorizontal && !isVertical) return false;

    // Word/line jumps are left to the platform.
    if (HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed) {
      return false;
    }

    // Super Editor embeds: no DocumentTextFlow — exit at first/last line.
    if (flow == null || segmentId == null) {
      return _handleStandaloneEdgeExit(event);
    }

    final selection = widget.controller.selection;
    if (!selection.isValid) return false;

    final extending = HardwareKeyboard.instance.isShiftPressed;
    final text = widget.controller.text;

    // Movement *within* a part is the text field's job, including its direction
    // — `rtlCaretMotionActions` flips that for Hebrew. This handler only decides
    // which edge of the part is the exit, which is mirrored in RTL: the left
    // arrow runs off the logical end of the text rather than its start.
    final rtl = _resolvedTextDirection(context) == TextDirection.rtl;
    final pressedLeft = key == LogicalKeyboardKey.arrowLeft;
    final movingBackward = isHorizontal
        ? (rtl ? !pressedLeft : pressedLeft)
        : key == LogicalKeyboardKey.arrowUp;

    // The moving end of the selection is what the arrow key acts on.
    final caret = extending
        ? selection.extentOffset
        : (movingBackward ? selection.start : selection.end);

    final here = DocumentTextPosition(segmentId, caret);

    // While extending, every horizontal step is driven here rather than by the
    // text field, so the document selection keeps tracking the moving end even
    // after it has crossed into another part.
    if (isHorizontal && extending) {
      if (flow.selection == null) flow.collapseTo(here);
      final target = movingBackward
          ? flow.positionBefore(here)
          : flow.positionAfter(here);
      if (target == null) return true;
      _applyFlowSelection(flow, target, extend: true);
      return true;
    }

    DocumentTextPosition? target;
    if (isHorizontal && movingBackward) {
      if (caret > 0) return false;
      target = flow.positionBefore(here);
    } else if (isHorizontal) {
      if (caret < text.length) return false;
      target = flow.positionAfter(here);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      if (!_caretOnFirstLine(caret)) return false;
      target = flow.positionAbove(
        here,
        preferredOffset: _caretColumn(caret),
        caretX: _caretGlobalX(caret),
      );
    } else {
      if (!_caretOnLastLine(caret)) return false;
      target = flow.positionBelow(
        here,
        preferredOffset: _caretColumn(caret),
        caretX: _caretGlobalX(caret),
      );
    }

    if (target == null) {
      // Document edge: swallow the key so focus does not escape the editor.
      return true;
    }

    if (extending && flow.selection == null) flow.collapseTo(here);
    _applyFlowSelection(flow, target, extend: extending);
    return true;
  }

  /// Moves the document caret and mirrors the result into the target field, so
  /// the field shows its own share of the selection with the caret at the
  /// moving end.
  void _applyFlowSelection(
    DocumentTextFlow flow,
    DocumentTextPosition target, {
    required bool extend,
  }) {
    _applyingFlowSelection = true;
    try {
      if (extend) {
        flow.extendTo(target);
      } else {
        flow.collapseTo(target);
      }

      final controller = flow.controllerFor(target.segmentId);
      final node = flow.focusNodeFor(target.segmentId);
      if (controller == null) return;

      if (node != null && !node.hasFocus && node.canRequestFocus) {
        node.requestFocus();
      }

      final length = controller.text.length;
      final offset = target.offset.clamp(0, length);
      final range = extend ? flow.selectionWithin(target.segmentId) : null;
      controller.selection = range == null
          ? TextSelection.collapsed(offset: offset)
          : TextSelection(
              baseOffset: range.start == offset ? range.end : range.start,
              extentOffset: offset,
            );
    } finally {
      _applyingFlowSelection = false;
    }
  }

  /// Screen x of the caret, so vertical movement into another part keeps the
  /// caret under the same column of pixels.
  double? _caretGlobalX(int caret) {
    final editable = _renderEditable();
    if (editable == null) return null;
    final rect = editable.getLocalRectForCaret(TextPosition(offset: caret));
    return editable.localToGlobal(rect.center).dx;
  }

  /// Column of the caret within its own visual line, used as a fallback when
  /// the target part is not laid out and pixel positions are unavailable.
  int _caretColumn(int caret) {
    final editable = _renderEditable();
    if (editable == null) return caret;
    final lineStart = editable.getLineAtOffset(TextPosition(offset: caret)).start;
    return caret - lineStart;
  }

  bool _caretOnFirstLine(int caret) {
    final editable = _renderEditable();
    if (editable == null) return true;
    final caretRect = editable.getLocalRectForCaret(TextPosition(offset: caret));
    final firstRect =
        editable.getLocalRectForCaret(const TextPosition(offset: 0));
    return (caretRect.top - firstRect.top).abs() < 0.5;
  }

  bool _caretOnLastLine(int caret) {
    final editable = _renderEditable();
    if (editable == null) return true;
    final caretRect = editable.getLocalRectForCaret(TextPosition(offset: caret));
    final lastRect = editable.getLocalRectForCaret(
      TextPosition(offset: widget.controller.text.length),
    );
    return (caretRect.top - lastRect.top).abs() < 0.5;
  }

  RenderEditable? _renderEditable() {
    if (!mounted) return null;
    final box = context.findRenderObject();
    if (box == null) return null;
    return _findRenderEditable(box);
  }

  /// Caret collapsed at offset 0 — climb to the previous part / merge / exit.
  /// Callers decide whether the field must also be empty.
  bool _shouldInvokeBackspaceAtStart() {
    final selection = widget.controller.selection;
    return selection.isValid &&
        selection.isCollapsed &&
        selection.start == 0;
  }

  void _openEmojiPicker() {
    if (!mounted) return;
    showTextEmojiPicker(
      context: context,
      searchHint: widget.emojiSearchHint,
      title: widget.emojiPickerTitle,
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final formatters = <TextInputFormatter>[
      if (widget.stripNewlines) _StripNewlinesFormatter(),
    ];

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (event.buttons == kPrimaryButton) {
          _pendingTapGlobal = event.position;
        }
        if (event.kind == PointerDeviceKind.mouse &&
            event.buttons == kSecondaryMouseButton) {
          // Freeze what the action will hit before the menu can move focus or
          // collapse the selection.
          _capturePendingMark();
          if (widget.onSecondaryTapDown != null) {
            widget.onSecondaryTapDown!(
              TapDownDetails(globalPosition: event.position),
            );
            return;
          }
          if (_focusNode.hasFocus ||
              BlockTextFocusRegistry.activeController == widget.controller) {
            FormatRange.capturePending(
              widget.controller.text,
              widget.controller.selection,
            );
          }
        }
      },
      child: MouseRegion(
        onHover: widget.descriptionRanges.isEmpty
            ? null
            : (event) => _handleDescriptionHover(event.localPosition),
        onExit: widget.descriptionRanges.isEmpty
            ? null
            : (_) => widget.onDescriptionHover?.call(null),
        child: GestureDetector(
          onDoubleTapDown: widget.descriptionRanges.isEmpty
              ? null
              : (details) {
                  final hit = _descriptionAt(details.localPosition);
                  if (hit != null) {
                    widget.onDescriptionDoubleTap?.call(hit);
                  }
                },
          child: AnimatedBuilder(
            animation: Listenable.merge([
              BlockTextFocusRegistry.menuSessionListenable,
              ?_flow,
            ]),
            builder: (context, _) {
              final inMenu = BlockTextFocusRegistry.isInMenuSession;
              final theme = Theme.of(context);
              final selectionColor = theme.textSelectionTheme.selectionColor ??
                  theme.colorScheme.primary.withValues(alpha: 0.3);
              // Overlay paints the mark (menu) or a multi-part selection — never
              // stack that on top of the field's own selection wash.
              final hideNativeSelection =
                  inMenu || (_flow?.spansSegments ?? false);

              // RTL solution — see rtl/RTL.md
              final textDirection = _resolvedTextDirection(context);
              final field = TextSelectionTheme(
                data: TextSelectionThemeData(
                  selectionColor:
                      hideNativeSelection ? Colors.transparent : selectionColor,
                  cursorColor: style.color,
                ),
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  style: style,
                  textDirection: textDirection,
                  textAlign: TextAlign.start,
                  textAlignVertical: widget.textAlignVertical,
                  maxLines: widget.maxLines,
                  minLines: widget.minLines,
                  // One scroll owner: the file pane's SingleChildScrollView.
                  scrollPhysics: const NeverScrollableScrollPhysics(),
                  scrollPadding: EdgeInsets.zero,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: widget.hintText,
                    hintStyle: style.copyWith(
                      color: style.color?.withValues(alpha: 0.35),
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                  textInputAction: widget.onEnter != null
                      ? TextInputAction.none
                      : widget.textInputAction,
                  onChanged: (_) => _notifyChanged(),
                  onSubmitted: widget.onSubmitted,
                  onTap: () {
                    _onFocusChanged();
                    _handleTap();
                  },
                  inputFormatters: formatters.isEmpty ? null : formatters,
                  contextMenuBuilder: (context, editableTextState) {
                    return const SizedBox.shrink();
                  },
                ),
              );

              var body = _withFlowVerticalIntents(
                wrapVisualCaretMotion(
                  textDirection: textDirection,
                  actions: _rtlMotionActions,
                  child: _withCrossSegmentHighlight(field),
                ),
              );

              if (widget.descriptionRanges.isNotEmpty) {
                body = _DescriptionUnderlineOverlay(
                  ranges: widget.descriptionRanges,
                  text: widget.controller.text,
                  style: style,
                  child: body,
                );
              }

              if (!inMenu) return body;

              final range = _frozenMarkRange();
              if (range == null) return body;

              return _FrozenSelectionOverlay(
                selection: range,
                selectionColor: selectionColor,
                child: body,
              );
            },
          ),
        ),
      ),
    );
  }

  DescriptionTextRange? _descriptionAt(Offset local) {
    final host = context.findRenderObject();
    if (host == null) return null;
    final editable = _findRenderEditable(host);
    if (editable == null) return null;
    final position = editable.getPositionForPoint(
      editable.localToGlobal(local),
    );
    final offset = position.offset;
    for (final range in widget.descriptionRanges) {
      if (offset >= range.start && offset < range.end) return range;
    }
    return null;
  }

  void _handleDescriptionHover(Offset local) {
    widget.onDescriptionHover?.call(_descriptionAt(local));
  }

  /// ↑/↓ at the first/last visual line when this field is not in a flow
  /// (embed under Super Editor). Returns false when the host has no handler.
  bool _handleStandaloneEdgeExit(KeyEvent event) {
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowUp &&
        key != LogicalKeyboardKey.arrowDown) {
      return false;
    }
    if (HardwareKeyboard.instance.isShiftPressed) return false;

    final selection = widget.controller.selection;
    // Single-line fields (info title) are one document line — always at both
    // edges. Don't require a valid selection; macOS may deliver moveUp: before
    // the caret is restored after a focus handoff.
    final singleLine = widget.maxLines == 1;
    if (!singleLine) {
      if (!selection.isValid || !selection.isCollapsed) return false;
      final caret = selection.extentOffset;
      if (key == LogicalKeyboardKey.arrowUp) {
        if (!_caretOnFirstLine(caret)) return false;
        if (widget.onArrowExitAbove == null) return false;
        widget.onArrowExitAbove!();
        return true;
      }
      if (!_caretOnLastLine(caret)) return false;
      if (widget.onArrowExitBelow == null) return false;
      widget.onArrowExitBelow!();
      return true;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      if (widget.onArrowExitAbove == null) return false;
      widget.onArrowExitAbove!();
      return true;
    }
    if (widget.onArrowExitBelow == null) return false;
    widget.onArrowExitBelow!();
    return true;
  }

  /// macOS sends vertical arrows as selection intents / IME selectors, not only
  /// key events. At a field edge we move through the document flow; otherwise
  /// the default EditableText action runs — except on single-line fields, where
  /// VerticalCaretMovementRun asserts (`isValid` false / one line).
  Widget _withFlowVerticalIntents(Widget child) {
    if (widget.segmentId == null &&
        widget.onArrowExitAbove == null &&
        widget.onArrowExitBelow == null) {
      return child;
    }
    final singleLine = widget.maxLines == 1;
    return Actions(
      actions: <Type, Action<Intent>>{
        ExtendSelectionVerticallyToAdjacentLineIntent: _FlowVerticalEdgeAction(
          (forward) {
            final synthetic = KeyDownEvent(
              physicalKey: forward
                  ? PhysicalKeyboardKey.arrowDown
                  : PhysicalKeyboardKey.arrowUp,
              logicalKey: forward
                  ? LogicalKeyboardKey.arrowDown
                  : LogicalKeyboardKey.arrowUp,
              timeStamp: Duration.zero,
            );
            return _handleFlowArrowKey(synthetic);
          },
          // Never fall through to EditableText on a single-line field.
          mayDeferToEditable: singleLine
              ? null
              : () => widget.controller.selection.isValid,
        ),
      },
      child: child,
    );
  }

  /// Paints this field's share of a selection that runs across several parts.
  ///
  /// A selection contained in one field is left to the text field's own
  /// painting; only a spanning selection needs drawing here, including on the
  /// focused field, whose native selection is kept collapsed to the caret.
  Widget _withCrossSegmentHighlight(Widget child) {
    final flow = _flow;
    final segmentId = _registeredSegmentId;
    if (flow == null || segmentId == null) return child;

    return AnimatedBuilder(
      animation: Listenable.merge([
        flow,
        BlockTextFocusRegistry.menuSessionListenable,
      ]),
      builder: (context, inner) {
        // While a menu is open the frozen mark is what will be acted on, and it
        // is painted by the overlay above; painting here too would double it.
        if (BlockTextFocusRegistry.isInMenuSession) return inner!;
        if (!flow.spansSegments) return inner!;
        final range = flow.selectionWithin(segmentId);
        if (range == null) return inner!;

        final theme = Theme.of(context);
        final selectionColor = theme.textSelectionTheme.selectionColor ??
            theme.colorScheme.primary.withValues(alpha: 0.3);

        return _FrozenSelectionOverlay(
          selection: range,
          selectionColor: selectionColor,
          child: inner!,
        );
      },
      child: child,
    );
  }
}

/// Highlights the frozen range using [RenderEditable] selection boxes.
class _FrozenSelectionOverlay extends StatefulWidget {
  const _FrozenSelectionOverlay({
    required this.selection,
    required this.selectionColor,
    required this.child,
  });

  final TextSelection selection;
  final Color selectionColor;
  final Widget child;

  @override
  State<_FrozenSelectionOverlay> createState() => _FrozenSelectionOverlayState();
}

class _FrozenSelectionOverlayState extends State<_FrozenSelectionOverlay> {
  List<Rect> _rects = const [];

  @override
  void initState() {
    super.initState();
    BlockTextFocusRegistry.menuSessionListenable.addListener(_scheduleMeasure);
  }

  @override
  void dispose() {
    BlockTextFocusRegistry.menuSessionListenable.removeListener(_scheduleMeasure);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _FrozenSelectionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selection != widget.selection) {
      _scheduleMeasure();
    }
  }

  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _measure();
    });
  }

  void _measure() {
    final host = context.findRenderObject() as RenderBox?;
    final editable = host == null ? null : _findRenderEditable(host);
    if (editable == null || host == null || !host.hasSize) {
      if (_rects.isNotEmpty) setState(() => _rects = const []);
      return;
    }

    if (!widget.selection.isValid || widget.selection.isCollapsed) {
      if (_rects.isNotEmpty) setState(() => _rects = const []);
      return;
    }

    final transform = editable.getTransformTo(host);
    final boxes = editable.getBoxesForSelection(widget.selection);
    final next = <Rect>[
      for (final box in boxes)
        MatrixUtils.transformRect(transform, box.toRect()),
    ];

    if (!FrozenSelectionPainter.rectsEqual(_rects, next)) {
      setState(() => _rects = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    _scheduleMeasure();
    return CustomPaint(
      foregroundPainter: FrozenSelectionPainter(
        rects: _rects,
        selectionColor: widget.selectionColor,
      ),
      child: widget.child,
    );
  }
}

RenderEditable? _findRenderEditable(RenderObject root) {
  if (root is RenderEditable) return root;
  RenderEditable? found;
  root.visitChildren((child) {
    found ??= _findRenderEditable(child);
  });
  return found;
}

class _DescriptionUnderlineOverlay extends StatefulWidget {
  const _DescriptionUnderlineOverlay({
    required this.ranges,
    required this.text,
    required this.style,
    required this.child,
  });

  final List<DescriptionTextRange> ranges;
  final String text;
  final TextStyle style;
  final Widget child;

  @override
  State<_DescriptionUnderlineOverlay> createState() =>
      _DescriptionUnderlineOverlayState();
}

class _DescriptionUnderlineOverlayState
    extends State<_DescriptionUnderlineOverlay> {
  List<Rect> _rects = const [];

  @override
  void didUpdateWidget(covariant _DescriptionUnderlineOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ranges != widget.ranges || oldWidget.text != widget.text) {
      _scheduleMeasure();
    }
  }

  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _measure();
    });
  }

  void _measure() {
    final host = context.findRenderObject() as RenderBox?;
    final editable = host == null ? null : _findRenderEditable(host);
    if (editable == null || host == null || !host.hasSize) {
      if (_rects.isNotEmpty) setState(() => _rects = const []);
      return;
    }
    final transform = editable.getTransformTo(host);
    final next = <Rect>[];
    for (final range in widget.ranges) {
      final start = range.start.clamp(0, widget.text.length);
      final end = range.end.clamp(0, widget.text.length);
      if (end <= start) continue;
      final boxes = editable.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end),
      );
      for (final box in boxes) {
        final rect = MatrixUtils.transformRect(transform, box.toRect());
        next.add(Rect.fromLTWH(rect.left, rect.bottom - 2, rect.width, 2));
      }
    }
    if (!FrozenSelectionPainter.rectsEqual(_rects, next)) {
      setState(() => _rects = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    _scheduleMeasure();
    return CustomPaint(
      foregroundPainter: _UnderlinePainter(rects: _rects),
      child: widget.child,
    );
  }
}

class _UnderlinePainter extends CustomPainter {
  _UnderlinePainter({required this.rects});

  final List<Rect> rects;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF3B82C4).withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;
    for (final rect in rects) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(1)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _UnderlinePainter oldDelegate) =>
      !FrozenSelectionPainter.rectsEqual(rects, oldDelegate.rects);
}

class _StripNewlinesFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.text.contains('\n')) return newValue;
    final cleaned = newValue.text.replaceAll('\n', ' ');
    return newValue.copyWith(
      text: cleaned,
      selection: TextSelection.collapsed(offset: cleaned.length),
      composing: TextRange.empty,
    );
  }
}

/// At a field edge, move through [DocumentTextFlow] / embed exits; otherwise
/// defer to EditableText (multi-line bodies only).
class _FlowVerticalEdgeAction
    extends Action<ExtendSelectionVerticallyToAdjacentLineIntent> {
  _FlowVerticalEdgeAction(
    this._tryFlowEdge, {
    bool Function()? mayDeferToEditable,
  }) : _mayDeferToEditable = mayDeferToEditable;

  final bool Function(bool forward) _tryFlowEdge;

  /// When null or returns false, never invoke EditableText's vertical action
  /// (avoids VerticalCaretMovementRun asserts on single-line / invalid sel).
  final bool Function()? _mayDeferToEditable;

  @override
  Object? invoke(ExtendSelectionVerticallyToAdjacentLineIntent intent) {
    if (_tryFlowEdge(intent.forward)) return null;
    final mayDefer = _mayDeferToEditable;
    if (mayDefer == null || !mayDefer()) return null;
    return callingAction?.invoke(intent);
  }

  @override
  bool isEnabled(ExtendSelectionVerticallyToAdjacentLineIntent intent) {
    // Keep enabled so macOS IME selectors hit us instead of a broken default.
    return true;
  }

  @override
  bool consumesKey(ExtendSelectionVerticallyToAdjacentLineIntent intent) =>
      true;
}
