/// Super Editor tap/drag hit-testing for mixed Hebrew + numbers — [RTL.md].
///
/// SE's `getDocumentPositionNearestToOffset` lands on a BiDi boundary (often
/// after a number run). Same geometry as [bidiAwareOffsetFromBoxes]: padding
/// beside the line → logical end on a tap; nearer visual edge when marking;
/// gaps snap to the nearest glyph run.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:super_editor/super_editor.dart';

import './empty_space_caret.dart';

SuperEditorContentTapDelegateFactory superEditorBidiCaretTapHandlerFactory =
    (SuperEditorContext editContext) => SuperEditorBidiCaretTapHandler(editContext);

/// Same as [superEditorBidiCaretTapHandlerFactory], plus a hook when the tap
/// lands on body text so an open object can hand writing back to Super Editor.
SuperEditorContentTapDelegateFactory bidiCaretTapHandler({
  VoidCallback? onBodyTextTap,
  VoidCallback? onBodyDoubleTap,
}) {
  return (SuperEditorContext editContext) => SuperEditorBidiCaretTapHandler(
    editContext,
    onBodyTextTap: onBodyTextTap,
    onBodyDoubleTap: onBodyDoubleTap,
  );
}

/// Document position under a pointer, corrected for Hebrew + numbers.
///
/// Returns null when the hit is not a text node (embeds, empty layout) so
/// Super Editor can keep its own handling.
DocumentPosition? bidiDocumentPosition({
  required Document document,
  required DocumentLayout layout,
  required Offset layoutOffset,
  required Offset globalOffset,
  required bool paddingGoesToLineEnd,
}) {
  final nearest = layout.getDocumentPositionNearestToOffset(layoutOffset);
  if (nearest == null) return null;
  final node = document.getNodeById(nearest.nodeId);
  if (node is! TextNode) return nearest;

  final component = layout.getComponentByNodeId(node.id);
  if (component is! TextComponentState) return nearest;
  final renderObject = component.context.findRenderObject();
  if (renderObject is! RenderBox) return nearest;

  final textLength = node.text.toPlainText().length;
  if (textLength <= 0) return nearest;

  List<Rect> boxes;
  try {
    boxes = [
      for (final box in component.textLayout.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: textLength),
      ))
        Rect.fromLTRB(box.left, box.top, box.right, box.bottom),
    ];
  } catch (_) {
    return nearest;
  }
  final local = renderObject.globalToLocal(globalOffset);
  final offset = bidiAwareOffsetFromBoxes(
    boxes: boxes,
    local: local,
    textLength: textLength,
    paddingGoesToLineEnd: paddingGoesToLineEnd,
    offsetAt: (probe) => _offsetAtLocal(
      layout: layout,
      box: renderObject,
      nodeId: node.id,
      local: probe,
      textLength: textLength,
    ),
    logicalLineEndAt: (probeOnLine) => _lineEndAtLocal(
      component: component,
      local: probeOnLine,
      textLength: textLength,
    ),
  );
  if (offset == null) return nearest;
  return DocumentPosition(
    nodeId: node.id,
    nodePosition: TextNodePosition(offset: offset),
  );
}

int _offsetAtLocal({
  required DocumentLayout layout,
  required RenderBox box,
  required String nodeId,
  required Offset local,
  required int textLength,
}) {
  final layoutOffset = layout.getDocumentOffsetFromAncestorOffset(
    box.localToGlobal(local),
  );
  final pos = layout.getDocumentPositionNearestToOffset(layoutOffset);
  if (pos == null || pos.nodeId != nodeId) return textLength;
  final nodePos = pos.nodePosition;
  if (nodePos is! TextNodePosition) return textLength;
  return nodePos.offset.clamp(0, textLength);
}

int _lineEndAtLocal({
  required TextComponentState component,
  required Offset local,
  required int textLength,
}) {
  try {
    final pos = component.textLayout.getPositionNearestToOffset(local);
    return component.textLayout
        .getPositionAtEndOfLine(pos)
        .offset
        .clamp(0, textLength);
  } catch (_) {
    return textLength;
  }
}

class SuperEditorBidiCaretTapHandler extends ContentTapDelegate {
  SuperEditorBidiCaretTapHandler(
    this.editContext, {
    this.onBodyTextTap,
    this.onBodyDoubleTap,
  });

  final SuperEditorContext editContext;

  /// Called before the caret is placed on a [TextNode], so an embed that
  /// still owns writing can release it. iOS Super Editor returns after a
  /// [TapHandlingInstruction.halt] without [FocusNode.requestFocus].
  final VoidCallback? onBodyTextTap;

  /// Phone: double-tap on body text should still open the mark menu when
  /// there is no word to mark (empty line / caret-only paste).
  final VoidCallback? onBodyDoubleTap;

  @override
  TapHandlingInstruction onTap(DocumentTapDetails details) {
    if (HardwareKeyboard.instance.isShiftPressed) {
      return _place(details, paddingGoesToLineEnd: false, extend: true);
    }
    return _place(details, paddingGoesToLineEnd: true, extend: false);
  }

  @override
  TapHandlingInstruction onDoubleTap(DocumentTapDetails details) {
    final pos = details.documentLayout.getDocumentPositionNearestToOffset(
      details.layoutOffset,
    );
    if (pos != null) {
      final node = editContext.document.getNodeById(pos.nodeId);
      if (node is TextNode) {
        onBodyDoubleTap?.call();
      }
    }
    return TapHandlingInstruction.continueHandling;
  }

  /// Desktop mouse drag is not routed through [ContentTapDelegate]. Pan
  /// handlers stay [TapHandlingInstruction.continueHandling] so iOS handle
  /// drags are not stolen; [SuperDocumentEditor] corrects drag geometry.
  @override
  TapHandlingInstruction onPanStart(DocumentTapDetails details) {
    return TapHandlingInstruction.continueHandling;
  }

  TapHandlingInstruction _place(
    DocumentTapDetails details, {
    required bool paddingGoesToLineEnd,
    required bool extend,
  }) {
    final pos = bidiDocumentPosition(
      document: editContext.document,
      layout: details.documentLayout,
      layoutOffset: details.layoutOffset,
      globalOffset: details.globalOffset,
      paddingGoesToLineEnd: paddingGoesToLineEnd,
    );
    if (pos == null) return TapHandlingInstruction.continueHandling;
    final node = editContext.document.getNodeById(pos.nodeId);
    if (node is! TextNode) {
      return TapHandlingInstruction.continueHandling;
    }
    onBodyTextTap?.call();
    if (extend) {
      final current = editContext.composer.selection;
      if (current == null) {
        _setSelection(
          DocumentSelection.collapsed(position: pos),
          SelectionChangeType.placeCaret,
        );
      } else {
        _setSelection(
          DocumentSelection(base: current.base, extent: pos),
          SelectionChangeType.expandSelection,
        );
      }
    } else {
      _setSelection(
        DocumentSelection.collapsed(position: pos),
        SelectionChangeType.placeCaret,
      );
    }
    return TapHandlingInstruction.halt;
  }

  void _setSelection(DocumentSelection selection, SelectionChangeType type) {
    editContext.editor.execute([
      ChangeSelectionRequest(
        selection,
        type,
        SelectionReason.userInteraction,
      ),
      const ClearComposingRegionRequest(),
    ]);
  }
}
