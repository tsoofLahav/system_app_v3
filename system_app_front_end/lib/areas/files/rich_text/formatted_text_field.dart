import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../../shared/utils/platform_text.dart';
import '../../objects/links/info_description_bubble.dart';
import '../editor/document_secondary_tap.dart';
import '../editor/document_text_flow.dart';
import '../editor/embed_exit_scope.dart';
import '../model/line_range.dart';
import './block_text_focus.dart';
import './format_range.dart';
import './frozen_selection_painter.dart';
import './rtl/rtl.dart';
import './span_text_editing_controller.dart';
import './text_links.dart';

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
    this.taskId,
    this.segmentId,
    this.documentBaseOffset = 0,
    this.descriptionRanges = const [],
    this.onDescriptionHover,
    this.onDescriptionDoubleTap,
    this.onDescriptionActivate,
    this.onArrowExitAbove,
    this.onArrowExitBelow,
    this.onArrowExitLeft,
    this.onArrowExitRight,
    this.hostKeyEvent,
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
  final int? taskId;

  /// Runs on this field's [FocusNode] **before** in-field editing (table/chart
  /// cells: Enter/Tab/edge arrows). Return [KeyEventResult.ignored] to let
  /// normal text / RTL motion run.
  final KeyEventResult Function(FocusNode node, KeyEvent event)? hostKeyEvent;

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

  /// When there is no [DocumentTextFlow], ← at the visual left edge of the
  /// text (offset 0 in LTR, end in RTL) calls this — e.g. table cell to the left.
  final VoidCallback? onArrowExitLeft;

  /// When there is no [DocumentTextFlow], → at the visual right edge of the
  /// text calls this — e.g. table cell to the right.
  final VoidCallback? onArrowExitRight;

  final List<DescriptionTextRange> descriptionRanges;
  final ValueChanged<DescriptionTextRange?>? onDescriptionHover;
  final ValueChanged<DescriptionTextRange>? onDescriptionDoubleTap;
  final ValueChanged<DescriptionTextRange>? onDescriptionActivate;

  @override
  State<FormattedTextField> createState() => _FormattedTextFieldState();
}

class _FormattedTextFieldState extends State<FormattedTextField> {
  late FocusNode _focusNode;
  bool _ownsFocus = false;
  bool _normalizingSelection = false;
  FocusOnKeyEventCallback? _editableKeyHandler;
  FocusOnKeyEventCallback? _installedKeyHandler;
  DocumentTextFlow? _flow;
  String? _registeredSegmentId;
  int? _registeredBaseOffset;
  bool _applyingFlowSelection = false;
  TextDirection? _detectedDirection;
  Offset? _pendingTapGlobal;
  late final Map<Type, Action<Intent>> _rtlMotionActions;
  bool _mutatingImeSentinel = false;
  bool _structureEnterArmed = true;
  OverlayEntry? _descriptionBubble;
  DescriptionTextRange? _hoveredDescription;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
    } else {
      _focusNode = FocusNode();
      _ownsFocus = true;
    }
    _rtlMotionActions = rtlCaretMotionActions(
      shouldFlip: _shouldFlipVisualArrows,
    );
    _focusNode.addListener(_onFocusChanged);
    widget.controller.addListener(_normalizeSelectionIfNeeded);
    widget.controller.addListener(_syncFlowFromLocalSelection);
    widget.controller.addListener(_syncParagraphDirection);
    widget.controller.addListener(_noteSelectionForMenu);
    widget.controller.addListener(_pinSentinelCaretIfNeeded);
    _detectedDirection = detectParagraphTextDirection(widget.controller.text);
    _syncDescriptionPaint();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _ensureKeyHandlerChained(),
    );
  }

  /// RTL solution: keep [TextField.textDirection] on the first strong character
  /// (see `rtl/RTL.md`).
  void _syncParagraphDirection() {
    final next = detectParagraphTextDirection(
      imeVisibleText(widget.controller.text),
    );
    if (next == _detectedDirection) return;
    setState(() => _detectedDirection = next);
  }

  void _noteSelectionForMenu() {
    BlockTextFocusRegistry.noteLiveSelection(widget.controller);
  }

  TextDirection _resolvedTextDirection(BuildContext context) {
    return resolveFieldTextDirection(
      widget.controller.text,
      Directionality.of(context),
    );
  }

  bool _shouldFlipVisualArrows() {
    if (!mounted) return false;
    final paragraph = _resolvedTextDirection(context);
    return caretRunIsRtl(
      editable: _renderEditable(),
      text: widget.controller.text,
      offset: widget.controller.selection.isValid
          ? widget.controller.selection.extentOffset
          : widget.controller.text.length,
      paragraphDir: paragraph,
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
    final changed =
        flow != _flow ||
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
      oldWidget.controller.removeListener(_noteSelectionForMenu);
      oldWidget.controller.removeListener(_pinSentinelCaretIfNeeded);
      widget.controller.addListener(_normalizeSelectionIfNeeded);
      widget.controller.addListener(_syncFlowFromLocalSelection);
      widget.controller.addListener(_syncParagraphDirection);
      widget.controller.addListener(_noteSelectionForMenu);
      widget.controller.addListener(_pinSentinelCaretIfNeeded);
      _detectedDirection = detectParagraphTextDirection(widget.controller.text);
      final previousId = _registeredSegmentId;
      if (previousId != null)
        _flow?.unregister(previousId, oldWidget.controller);
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
      _installedKeyHandler = null;
      _editableKeyHandler = null;
    }
    _attachToFlow(_flow);
    _syncDescriptionPaint();
    if (oldWidget.focusNode != widget.focusNode ||
        _focusNode.onKeyEvent != _installedKeyHandler) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _ensureKeyHandlerChained(),
      );
    }
  }

  void _syncDescriptionPaint() {
    final controller = widget.controller;
    if (controller is! SpanTextEditingController) return;
    controller.setDescriptionPaintRanges([
      for (final range in widget.descriptionRanges)
        (start: range.start, end: range.end),
    ]);
  }

  @override
  void dispose() {
    if (_focusNode.onKeyEvent == _installedKeyHandler) {
      _focusNode.onKeyEvent = _editableKeyHandler;
    }
    final registeredId = _registeredSegmentId;
    if (registeredId != null)
      _flow?.unregister(registeredId, widget.controller);
    widget.controller.removeListener(_normalizeSelectionIfNeeded);
    widget.controller.removeListener(_syncFlowFromLocalSelection);
    widget.controller.removeListener(_syncParagraphDirection);
    widget.controller.removeListener(_noteSelectionForMenu);
    widget.controller.removeListener(_pinSentinelCaretIfNeeded);
    _focusNode.removeListener(_onFocusChanged);
    _stripEmptyImeSentinel(rebuild: false);
    BlockTextFocusRegistry.unregister(widget.controller);
    _hideDescriptionBubble();
    if (_ownsFocus) _focusNode.dispose();
    super.dispose();
  }

  /// Installs our handler in front of EditableText's **once**. Tear-offs of
  /// [_chainedKeyHandler] are not identical, so comparing them with `==` and
  /// re-wrapping on every rebuild stacked the chain until Arrow Up overflowed.
  void _ensureKeyHandlerChained() {
    if (!mounted) return;
    final current = _focusNode.onKeyEvent;
    final installed = _installedKeyHandler;
    if (installed != null) {
      if (current == installed) return;
      if (current != _editableKeyHandler) {
        _editableKeyHandler = current;
      }
      _focusNode.onKeyEvent = installed;
      return;
    }
    _editableKeyHandler = current;
    _installedKeyHandler = _chainedKeyHandler;
    _focusNode.onKeyEvent = _installedKeyHandler;
  }

  KeyEventResult _chainedKeyHandler(FocusNode node, KeyEvent event) {
    final host = widget.hostKeyEvent;
    if (host != null) {
      final hosted = host(node, event);
      if (hosted == KeyEventResult.handled) return hosted;
    }
    final result = _onFocusKeyEvent(node, event);
    if (result == KeyEventResult.handled) return result;
    final editable = _editableKeyHandler;
    if (editable != null && editable != _installedKeyHandler) {
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
        taskId: widget.taskId,
        flow: _flow,
      );
      // File pane owns scrolling — keep the caret in view without letting each
      // EditableText scroll as its own surface.
      _ensureVisibleInFilePane();
      _ensureEmptyImeSentinel();
    } else {
      if ((BlockTextFocusRegistry.isInMenuSession ||
              BlockTextFocusRegistry.isInEmojiPickerSession) &&
          BlockTextFocusRegistry.activeController == widget.controller) {
        return;
      }
      _stripEmptyImeSentinel();
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
    if (_mutatingImeSentinel) return;
    final controller = widget.controller;
    if (controller.text == imeEmptySentinel) {
      widget.onChanged?.call('');
      return;
    }
    if (controller is SpanTextEditingController) {
      controller.ensureSpansMatchText();
    }
    widget.onChanged?.call(imeVisibleText(controller.text));
  }

  bool get _handlesStructureEnter =>
      widget.onEnter != null || widget.hostKeyEvent != null;

  bool get _usesEmptyImeSentinel => widget.onBackspaceAtStart != null;

  void _ensureEmptyImeSentinel() {
    if (!_usesEmptyImeSentinel) return;
    if (!_focusNode.hasFocus) return;
    if (!imeFieldLooksEmpty(widget.controller.text)) return;
    if (widget.controller.text == imeEmptySentinel) {
      _pinEmptyImeCaret();
      return;
    }
    _mutatingImeSentinel = true;
    widget.controller.value = const TextEditingValue(
      text: imeEmptySentinel,
      selection: TextSelection.collapsed(offset: 1),
    );
    _mutatingImeSentinel = false;
    if (mounted) setState(() {});
  }

  void _stripEmptyImeSentinel({bool rebuild = true}) {
    if (widget.controller.text != imeEmptySentinel) return;
    _mutatingImeSentinel = true;
    widget.controller.value = const TextEditingValue(
      text: '',
      selection: TextSelection.collapsed(offset: 0),
    );
    _mutatingImeSentinel = false;
    if (rebuild && mounted) setState(() {});
  }

  void _pinSentinelCaretIfNeeded() {
    if (_mutatingImeSentinel) return;
    if (widget.controller.text != imeEmptySentinel) return;
    _pinEmptyImeCaret();
  }

  void _pinEmptyImeCaret() {
    final selection = widget.controller.selection;
    if (selection.isValid &&
        selection.isCollapsed &&
        selection.baseOffset == 1) {
      return;
    }
    _mutatingImeSentinel = true;
    widget.controller.selection = const TextSelection.collapsed(offset: 1);
    _mutatingImeSentinel = false;
  }

  /// Phone IME Return inserts a newline instead of a KeyEvent. Same for
  /// [onSubmitted] when the field is treated as single-line.
  void _invokeStructureEnter() {
    if (!_handlesStructureEnter) return;
    if (!_structureEnterArmed) return;
    _structureEnterArmed = false;
    scheduleMicrotask(() => _structureEnterArmed = true);
    _stripEmptyImeSentinel();
    if (widget.onEnter != null) {
      widget.onEnter!();
      return;
    }
    final host = widget.hostKeyEvent;
    if (host == null) return;
    host(
      _focusNode,
      KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.enter,
        logicalKey: LogicalKeyboardKey.enter,
        timeStamp: Duration.zero,
      ),
    );
  }

  void _invokeEmptyBackspace() {
    final callback = widget.onBackspaceAtStart;
    if (callback == null) return;
    _stripEmptyImeSentinel();
    unawaited(callback());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focusNode.hasFocus) return;
      _ensureEmptyImeSentinel();
    });
  }

  void _normalizeSelectionIfNeeded() {
    if (_normalizingSelection) return;
    final controller = widget.controller;
    final normalized = normalizeTextSelection(
      controller.text,
      controller.selection,
    );
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

    if ((event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
        HardwareKeyboard.instance.isShiftPressed) {
      final exit = EmbedExitScope.maybeOf(context);
      if (exit != null) {
        exit.onExit(exit.nodeId);
        return KeyEventResult.handled;
      }
    }

    final isMeta = HardwareKeyboard.instance.isMetaPressed;
    if (isMeta &&
        !HardwareKeyboard.instance.isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyC) {
      _copySelection();
      return KeyEventResult.handled;
    }

    if (isMeta &&
        !HardwareKeyboard.instance.isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyX) {
      _cutSelection();
      return KeyEventResult.handled;
    }

    if (isMeta &&
        !HardwareKeyboard.instance.isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyA) {
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
        _handlesStructureEnter) {
      _invokeStructureEnter();
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
        widget.onBackspaceAtStart != null &&
        (imeFieldLooksEmpty(widget.controller.text) ||
            _shouldInvokeBackspaceAtStart())) {
      _invokeEmptyBackspace();
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
    final start = selection.start < selection.end
        ? selection.start
        : selection.end;
    final end = selection.start < selection.end
        ? selection.end
        : selection.start;
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
    if (BlockTextFocusRegistry.activeController != widget.controller)
      return null;
    return frozenRange.selection;
  }

  /// Right-clicking outside an existing mark moves the caret here first, so the
  /// action targets the line the user pointed at rather than a stale mark
  /// somewhere else in the file.
  void _capturePendingMark(Offset globalPosition) {
    // Always register this field first — Super Editor embeds often have no
    // DocumentTextFlow, and without register capturePendingMark resolves the
    // wrong controller (or nothing) so the mark looks like "the whole object".
    BlockTextFocusRegistry.register(
      controller: widget.controller,
      changed: _notifyChanged,
      blockContent: widget.blockContent,
      fontSize: widget.style.fontSize ?? 12.5,
      focusNode: _focusNode,
      blockId: widget.blockId,
      taskId: widget.taskId,
      flow: _flow,
    );

    final offset = _offsetForGlobal(globalPosition);
    if (offset != null && !_clickIsInsideExistingMark(offset)) {
      // Same as Super Editor: drop a stale snapshot, place the caret, expand
      // to the line at the pointer, then freeze.
      BlockTextFocusRegistry.discardTransientMark();
      final line = LineRange.resolve(
        widget.controller.text,
        TextSelection.collapsed(offset: offset),
      );
      widget.controller.selection = line.isValid
          ? line.selection
          : TextSelection.collapsed(offset: offset);
      final flow = _flow;
      final segmentId = _registeredSegmentId;
      if (flow != null && segmentId != null) {
        flow.collapseTo(DocumentTextPosition(segmentId, line.start));
        if (line.isValid) {
          flow.extendTo(DocumentTextPosition(segmentId, line.end));
        }
      }
    }
    BlockTextFocusRegistry.capturePendingMark();
  }

  int? _offsetForGlobal(Offset global) {
    final host = context.findRenderObject();
    if (host == null) return null;
    final editable = _findRenderEditable(host);
    if (editable == null) return null;
    final offset = editable.getPositionForPoint(global).offset;
    return offset.clamp(0, widget.controller.text.length);
  }

  bool _clickIsInsideExistingMark(int offset) {
    final flow = _flow;
    final segmentId = _registeredSegmentId;
    if (flow != null && segmentId != null) {
      final marked = flow.selectionWithin(segmentId);
      if (marked != null && offset >= marked.start && offset < marked.end) {
        return true;
      }
    }
    final sel = widget.controller.selection;
    return sel.isValid &&
        !sel.isCollapsed &&
        offset >= sel.start &&
        offset < sel.end;
  }

  /// Shift+click extends the document selection into this part; a plain click
  /// drops a selection that was covering several parts.
  ///
  /// RTL solution (`rtl/RTL.md`): padding beside the line → logical end;
  /// BiDi gaps snap to the nearest glyph; end-of-line taps keep affinity on
  /// that line. Same turn, no post-frame.
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
        final next = embedCaretForTap(
          editable: editable,
          globalPosition: tapGlobal,
          textLength: widget.controller.text.length,
        );
        offset = next.extentOffset;
        widget.controller.selection = next;
        if (flow != null && segmentId != null) {
          flow.collapseTo(DocumentTextPosition(segmentId, offset));
        }
      }
      final hostBox = context.findRenderObject();
      if (hostBox is RenderBox) {
        final local = hostBox.globalToLocal(tapGlobal);
        final hit = _descriptionAt(local);
        if (hit != null) {
          _activateDescription(hit);
        } else {
          _openWebLinkAt(local);
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
    final isHorizontal =
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight;
    final isVertical =
        key == LogicalKeyboardKey.arrowUp ||
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
    final lineStart = editable
        .getLineAtOffset(TextPosition(offset: caret))
        .start;
    return caret - lineStart;
  }

  bool _caretOnFirstLine(int caret) {
    final editable = _renderEditable();
    if (editable == null) return true;
    final caretRect = editable.getLocalRectForCaret(
      TextPosition(offset: caret),
    );
    final firstRect = editable.getLocalRectForCaret(
      const TextPosition(offset: 0),
    );
    return (caretRect.top - firstRect.top).abs() < 0.5;
  }

  bool _caretOnLastLine(int caret) {
    final editable = _renderEditable();
    if (editable == null) return true;
    final caretRect = editable.getLocalRectForCaret(
      TextPosition(offset: caret),
    );
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
    return selection.isValid && selection.isCollapsed && selection.start == 0;
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final formatters = <TextInputFormatter>[
      if (_handlesStructureEnter || _usesEmptyImeSentinel)
        _ImeStructureKeyFormatter(
          wantEnter: _handlesStructureEnter,
          holdEmptySentinel: _usesEmptyImeSentinel && _focusNode.hasFocus,
          onEnter: _invokeStructureEnter,
          onEmptyBackspace: _invokeEmptyBackspace,
        ),
      if (widget.stripNewlines) _StripNewlinesFormatter(),
    ];

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (event.buttons == kPrimaryButton) {
          _pendingTapGlobal = event.position;
        }
        final isSecondary = (event.buttons & kSecondaryMouseButton) != 0;
        if (isSecondary) {
          // Freeze what the action will hit before the menu can move focus or
          // collapse the selection.
          _capturePendingMark(event.position);
          if (widget.onSecondaryTapDown != null) {
            // Tell Super Editor's translucent secondary-tap handler to stand
            // down — otherwise the document text menu opens on top and
            // clobbers the frozen mark.
            DocumentSecondaryTap.markEmbedHandled();
            widget.onSecondaryTapDown!(
              TapDownDetails(globalPosition: event.position),
            );
            return;
          }
          DocumentSecondaryTap.clearEmbedHandled();
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
            : (_) {
                widget.onDescriptionHover?.call(null);
                _hideDescriptionBubble();
              },
        child: GestureDetector(
          onDoubleTapDown: widget.descriptionRanges.isEmpty
              ? null
              : (details) {
                  final hit = _descriptionAt(details.localPosition);
                  if (hit != null) _activateDescription(hit);
                },
          child: AnimatedBuilder(
            animation: Listenable.merge([
              BlockTextFocusRegistry.menuSessionListenable,
              ?_flow,
            ]),
            builder: (context, _) {
              final inMenu = BlockTextFocusRegistry.isInMenuSession;
              final theme = Theme.of(context);
              final selectionColor =
                  theme.textSelectionTheme.selectionColor ??
                  theme.colorScheme.primary.withValues(alpha: 0.3);
              // Overlay paints the mark (menu) or a multi-part selection — never
              // stack that on top of the field's own selection wash.
              final hideNativeSelection =
                  inMenu || (_flow?.spansSegments ?? false);

              // RTL solution — see rtl/RTL.md
              final textDirection = _resolvedTextDirection(context);
              final field = TextSelectionTheme(
                data: TextSelectionThemeData(
                  selectionColor: hideNativeSelection
                      ? Colors.transparent
                      : selectionColor,
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
                    hintText:
                        (_usesEmptyImeSentinel &&
                            widget.controller.text == imeEmptySentinel)
                        ? null
                        : widget.hintText,
                    hintStyle: style.copyWith(
                      color: style.color?.withValues(alpha: 0.35),
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                  textInputAction: _handlesStructureEnter
                      ? TextInputAction.newline
                      : widget.textInputAction,
                  onChanged: (_) => _notifyChanged(),
                  onSubmitted: (value) {
                    if (_handlesStructureEnter) {
                      _invokeStructureEnter();
                      return;
                    }
                    widget.onSubmitted?.call(value);
                  },
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
              if (_usesEmptyImeSentinel && widget.hintText != null) {
                final showHint = imeFieldLooksEmpty(widget.controller.text);
                body = Stack(
                  children: [
                    body,
                    IgnorePointer(
                      child: Opacity(
                        opacity: showHint ? 1 : 0,
                        child: Text(
                          widget.hintText!,
                          style: style.copyWith(
                            color: style.color?.withValues(alpha: 0.35),
                          ),
                        ),
                      ),
                    ),
                  ],
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

  void _openWebLinkAt(Offset local) {
    final host = context.findRenderObject();
    if (host == null) return;
    final editable = _findRenderEditable(host);
    if (editable == null) return;
    final controller = widget.controller;
    if (controller is! SpanTextEditingController) return;
    final position = editable.getPositionForPoint(
      editable.localToGlobal(local),
    );
    final url = urlAtSpanOffset(controller.spans, position.offset);
    if (url == null) return;
    unawaited(openWebLink(url));
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
    final hit = _descriptionAt(local);
    widget.onDescriptionHover?.call(hit);
    _syncDescriptionBubble(hit, local);
  }

  void _activateDescription(DescriptionTextRange hit) {
    _hideDescriptionBubble();
    widget.onDescriptionActivate?.call(hit);
    widget.onDescriptionDoubleTap?.call(hit);
  }

  void _syncDescriptionBubble(DescriptionTextRange? hit, Offset local) {
    if (hit == null) {
      _hideDescriptionBubble();
      return;
    }
    if (_hoveredDescription != null &&
        identical(_hoveredDescription!.link, hit.link) &&
        _hoveredDescription!.start == hit.start &&
        _hoveredDescription!.end == hit.end) {
      return;
    }
    _hoveredDescription = hit;
    _hideDescriptionBubble(clearHover: false);
    final peer = hit.link['peer'];
    final title = peer is Map ? '${peer['title'] ?? ''}' : '';
    final body = peer is Map ? '${peer['body'] ?? ''}' : '';
    if (title.isEmpty && body.isEmpty) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final origin = box.localToGlobal(local);
    _descriptionBubble = OverlayEntry(
      builder: (ctx) {
        return Positioned(
          left: origin.dx,
          top: origin.dy + 18,
          child: IgnorePointer(
            child: InfoDescriptionBubble(title: title, body: body),
          ),
        );
      },
    );
    overlay.insert(_descriptionBubble!);
  }

  void _hideDescriptionBubble({bool clearHover = true}) {
    _descriptionBubble?.remove();
    _descriptionBubble = null;
    if (clearHover) _hoveredDescription = null;
  }

  /// ↑/↓/←/→ at a visual edge when this field is not in a flow (embed under
  /// Super Editor). Returns false when the host has no handler for that edge.
  bool _handleStandaloneEdgeExit(KeyEvent event) {
    final key = event.logicalKey;
    final isUp = key == LogicalKeyboardKey.arrowUp;
    final isDown = key == LogicalKeyboardKey.arrowDown;
    final isLeft = key == LogicalKeyboardKey.arrowLeft;
    final isRight = key == LogicalKeyboardKey.arrowRight;
    if (!isUp && !isDown && !isLeft && !isRight) return false;
    if (HardwareKeyboard.instance.isShiftPressed) return false;

    final selection = widget.controller.selection;

    if (isLeft || isRight) {
      if (widget.onArrowExitLeft == null && widget.onArrowExitRight == null) {
        return false;
      }
      if (!selection.isValid || !selection.isCollapsed) return false;
      final caret = selection.extentOffset;
      final textLen = widget.controller.text.length;
      final rtl = _resolvedTextDirection(context) == TextDirection.rtl;
      // Physical grid nav: left/right keys match on-screen edges.
      final atVisualLeft = rtl ? caret >= textLen : caret <= 0;
      final atVisualRight = rtl ? caret <= 0 : caret >= textLen;
      if (isLeft && atVisualLeft) {
        if (widget.onArrowExitLeft == null) return false;
        widget.onArrowExitLeft!();
        return true;
      }
      if (isRight && atVisualRight) {
        if (widget.onArrowExitRight == null) return false;
        widget.onArrowExitRight!();
        return true;
      }
      return false;
    }

    // Single-line fields (info title) are one document line — always at both
    // edges. Don't require a valid selection; macOS may deliver moveUp: before
    // the caret is restored after a focus handoff.
    final singleLine = widget.maxLines == 1;
    if (!singleLine) {
      if (!selection.isValid || !selection.isCollapsed) return false;
      final caret = selection.extentOffset;
      if (isUp) {
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

    if (isUp) {
      if (widget.onArrowExitAbove == null) return false;
      widget.onArrowExitAbove!();
      return true;
    }
    if (widget.onArrowExitBelow == null) return false;
    widget.onArrowExitBelow!();
    return true;
  }

  /// macOS often delivers arrows as selection intents / IME selectors, not only
  /// key events. At a field edge we move to the host (table cell / flow);
  /// otherwise EditableText runs — except single-line vertical, which asserts.
  ///
  /// Parent of [wrapVisualCaretMotion]: in RTL the flip action calls *this*
  /// with a flipped [ExtendSelectionByCharacterIntent], so [forward] here means
  /// toward higher string offset (visual left in RTL, visual right in LTR).
  Widget _withFlowVerticalIntents(Widget child) {
    if (widget.segmentId == null &&
        widget.onArrowExitAbove == null &&
        widget.onArrowExitBelow == null &&
        widget.onArrowExitLeft == null &&
        widget.onArrowExitRight == null) {
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
        ExtendSelectionByCharacterIntent: _StandaloneHorizontalEdgeAction(
          tryEdge: _tryHorizontalEdgeExitForIntent,
        ),
      },
      child: child,
    );
  }

  /// Intent-path edge exit. [towardHigherOffset] is after any RTL flip.
  bool _tryHorizontalEdgeExitForIntent(
    ExtendSelectionByCharacterIntent intent,
  ) {
    if (!intent.collapseSelection) return false;
    if (widget.onArrowExitLeft == null && widget.onArrowExitRight == null) {
      return false;
    }
    final selection = widget.controller.selection;
    if (!selection.isValid || !selection.isCollapsed) return false;
    final caret = selection.extentOffset;
    final textLen = widget.controller.text.length;
    final rtl = _resolvedTextDirection(context) == TextDirection.rtl;
    if (intent.forward) {
      if (caret < textLen) return false;
      // Higher-offset edge: visual right (LTR) / visual left (RTL).
      if (rtl) {
        if (widget.onArrowExitLeft == null) return false;
        widget.onArrowExitLeft!();
        return true;
      }
      if (widget.onArrowExitRight == null) return false;
      widget.onArrowExitRight!();
      return true;
    }
    if (caret > 0) return false;
    if (rtl) {
      if (widget.onArrowExitRight == null) return false;
      widget.onArrowExitRight!();
      return true;
    }
    if (widget.onArrowExitLeft == null) return false;
    widget.onArrowExitLeft!();
    return true;
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
        final selectionColor =
            theme.textSelectionTheme.selectionColor ??
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
  State<_FrozenSelectionOverlay> createState() =>
      _FrozenSelectionOverlayState();
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
    BlockTextFocusRegistry.menuSessionListenable.removeListener(
      _scheduleMeasure,
    );
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

class _ImeStructureKeyFormatter extends TextInputFormatter {
  _ImeStructureKeyFormatter({
    required this.wantEnter,
    required this.holdEmptySentinel,
    required this.onEnter,
    required this.onEmptyBackspace,
  });

  final bool wantEnter;
  final bool holdEmptySentinel;
  final VoidCallback onEnter;
  final VoidCallback onEmptyBackspace;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (wantEnter && imeInsertedSingleNewline(oldValue.text, newValue.text)) {
      scheduleMicrotask(onEnter);
      if (holdEmptySentinel && imeFieldLooksEmpty(oldValue.text)) {
        return const TextEditingValue(
          text: imeEmptySentinel,
          selection: TextSelection.collapsed(offset: 1),
        );
      }
      return TextEditingValue(
        text: imeVisibleText(oldValue.text),
        selection: oldValue.selection,
        composing: TextRange.empty,
      );
    }

    if (holdEmptySentinel &&
        imeDeletedEmptySentinel(oldValue.text, newValue.text)) {
      scheduleMicrotask(onEmptyBackspace);
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    if (oldValue.text == imeEmptySentinel &&
        newValue.text.startsWith(imeEmptySentinel) &&
        newValue.text.length > 1) {
      final typed = newValue.text.replaceFirst(imeEmptySentinel, '');
      final caret = (newValue.selection.baseOffset - 1).clamp(0, typed.length);
      return TextEditingValue(
        text: typed,
        selection: TextSelection.collapsed(offset: caret),
        composing: TextRange.empty,
      );
    }

    if (holdEmptySentinel && newValue.text.isEmpty) {
      return const TextEditingValue(
        text: imeEmptySentinel,
        selection: TextSelection.collapsed(offset: 1),
      );
    }

    return newValue;
  }
}

/// Invisible placeholder so the iOS IME will deliver a delete on an empty
/// object field (otherwise `deleteBackward` is a no-op).
const imeEmptySentinel = '\u200B';

String imeVisibleText(String text) => text.replaceAll(imeEmptySentinel, '');

bool imeFieldLooksEmpty(String text) => imeVisibleText(text).isEmpty;

@visibleForTesting
bool imeInsertedSingleNewline(String previous, String next) {
  if (!next.contains('\n')) return false;
  final previousVisible = imeVisibleText(previous);
  for (var i = 0; i < next.length; i++) {
    if (next.codeUnitAt(i) != 0x0A) continue;
    if (imeVisibleText(next.replaceRange(i, i + 1, '')) == previousVisible) {
      return true;
    }
  }
  return false;
}

@visibleForTesting
bool imeDeletedEmptySentinel(String previous, String next) {
  return previous == imeEmptySentinel && next.isEmpty;
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

/// ←/→ at a text edge (table/graph cells) — macOS character-selection intents.
class _StandaloneHorizontalEdgeAction
    extends Action<ExtendSelectionByCharacterIntent> {
  _StandaloneHorizontalEdgeAction({required this.tryEdge});

  final bool Function(ExtendSelectionByCharacterIntent intent) tryEdge;

  @override
  Object? invoke(ExtendSelectionByCharacterIntent intent) {
    if (tryEdge(intent)) return null;
    return callingAction?.invoke(intent);
  }

  @override
  bool isEnabled(ExtendSelectionByCharacterIntent intent) => true;

  @override
  bool consumesKey(ExtendSelectionByCharacterIntent intent) => true;
}
