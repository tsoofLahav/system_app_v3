/// Super Editor single-tap padding correction — [RTL.md].
/// Glyph clicks, gaps, Shift-click and selection drags stay native to SE.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_text_layout/super_text_layout.dart';

import './empty_space_caret.dart';

SuperEditorContentTapDelegateFactory superEditorBidiCaretTapHandlerFactory =
    (SuperEditorContext editContext) =>
        SuperEditorBidiCaretTapHandler(editContext);

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

/// Corrected position only for empty padding beside a text line.
///
/// Returns null on glyphs, inter-run gaps, and non-text components so
/// Super Editor can keep its own handling.
DocumentPosition? paddingDocumentPosition({
  required Document document,
  required DocumentLayout layout,
  required Offset layoutOffset,
  required Offset globalOffset,
}) {
  final nearest = layout.getDocumentPositionNearestToOffset(layoutOffset);
  if (nearest == null) return null;
  final node = document.getNodeById(nearest.nodeId);
  if (node is! TextNode) return null;

  // Paragraphs and list items expose proxy components, not TextComponentState.
  // Resolve the leaf and use its coordinate space for both boxes and taps.
  Object? candidate = layout.getComponentByNodeId(node.id);
  while (candidate is ProxyTextComposable) {
    candidate = candidate.childTextComposable;
  }
  final component = candidate;
  if (component is! TextComponentState) return null;
  final renderObject = component.context.findRenderObject();
  if (renderObject is! RenderBox) return null;

  final textLength = node.text.toPlainText().length;
  if (textLength <= 0) return null;

  List<Rect> boxes;
  try {
    boxes = [
      for (final box in component.textLayout.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: textLength),
      ))
        Rect.fromLTRB(box.left, box.top, box.right, box.bottom),
    ];
  } catch (_) {
    return null;
  }
  final local = renderObject.globalToLocal(globalOffset);
  final offset = emptySpaceCaretOffsetFromBoxes(
    boxes: boxes,
    local: local,
    textLength: textLength,
    logicalLineEndAt: (probe) => _lineEndAtLocal(
      component: component,
      local: probe,
      text: node.text.toPlainText(),
    ),
  );
  if (offset == null) return null;
  return DocumentPosition(
    nodeId: node.id,
    nodePosition: TextNodePosition(
      offset: offset,
      affinity: TextAffinity.upstream,
    ),
  );
}

int _lineEndAtLocal({
  required TextComponentState component,
  required Offset local,
  required String text,
}) => logicalLineEndForTextLayout(component.textLayout, text, local);

/// SE's getPositionAtEndOfLine probes the physical right edge. That is the
/// logical start for Hebrew. Resolve the last logical grapheme on the aimed
/// visual line from the renderer's own selection boxes instead.
int logicalLineEndForTextLayout(TextLayout layout, String text, Offset local) {
  if (text.isEmpty) return 0;
  var offset = 0;
  var result = 0;
  var bestDistance = double.infinity;
  for (final grapheme in text.characters) {
    final end = offset + grapheme.length;
    if (grapheme != '\n' && grapheme != '\r\n') {
      final boxes = layout.getBoxesForSelection(
        TextSelection(baseOffset: offset, extentOffset: end),
      );
      for (final box in boxes) {
        final distance = local.dy < box.top
            ? box.top - local.dy
            : local.dy > box.bottom
            ? local.dy - box.bottom
            : 0.0;
        if (distance < bestDistance - 0.5) {
          bestDistance = distance;
          result = end;
        } else if ((distance - bestDistance).abs() <= 0.5 && end > result) {
          result = end;
        }
      }
    }
    offset = end;
  }
  return bestDistance.isFinite
      ? result
      : layout.getPositionNearestToOffset(local).offset.clamp(0, text.length);
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
    final nearest = details.documentLayout.getDocumentPositionNearestToOffset(
      details.layoutOffset,
    );
    if (nearest != null &&
        editContext.document.getNodeById(nearest.nodeId) is TextNode) {
      onBodyTextTap?.call();
    }
    if (HardwareKeyboard.instance.isShiftPressed)
      return TapHandlingInstruction.continueHandling;
    final pos = paddingDocumentPosition(
      document: editContext.document,
      layout: details.documentLayout,
      layoutOffset: details.layoutOffset,
      globalOffset: details.globalOffset,
    );
    if (pos == null) return TapHandlingInstruction.continueHandling;
    _setSelection(
      DocumentSelection.collapsed(position: pos),
      SelectionChangeType.placeCaret,
    );
    return TapHandlingInstruction.halt;
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
  /// drags and desktop selection stay native to Super Editor.
  @override
  TapHandlingInstruction onPanStart(DocumentTapDetails details) {
    return TapHandlingInstruction.continueHandling;
  }

  void _setSelection(DocumentSelection selection, SelectionChangeType type) {
    editContext.editor.execute([
      ChangeSelectionRequest(selection, type, SelectionReason.userInteraction),
      const ClearComposingRegionRequest(),
    ]);
  }
}
